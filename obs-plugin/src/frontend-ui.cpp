/*
 * Frontend UI: a live health readout in OBS's status bar (fps · Mb/s ·
 * latency, next to OBS's own stats) plus a "LensLink" dock with one row
 * per source, fed by the snapshots ios-camera-source.c keeps anyway.
 *
 * Two deliberate choices keep this portable and optional:
 *
 * - The obs-frontend-api symbols are resolved AT RUNTIME from the running
 *   process (dlsym / GetProcAddress). The plugin never links the frontend
 *   library — the same binary loads in OBS builds without a frontend
 *   (headless, older) and the UI just stays off. Only the header is
 *   needed at compile time, for the types.
 * - No Q_OBJECT: the timer binds a lambda, so no moc, and the plugin's
 *   plain CMake stays plain.
 *
 * Everything here runs on the Qt UI thread (frontend event callbacks and
 * the QTimer both live there); the only cross-thread traffic is
 * lenslink_health_enum, which locks internally.
 */

#include <obs-module.h>
#include <obs-frontend-api.h>
#include <util/platform.h>

#include <QCheckBox>
#include <QClipboard>
#include <QComboBox>
#include <QDateTime>
#include <QHBoxLayout>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMouseEvent>
#include <QPainter>
#include <QSignalBlocker>
#include <QSlider>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QGuiApplication>
#include <QLabel>
#include <QMainWindow>
#include <QPushButton>
#include <QSpinBox>
#include <QStatusBar>
#include <QStringList>
#include <QTimer>
#include <QVBoxLayout>

#include <functional>
#include <string>
#include <unordered_map>

extern "C" {
#include "camera-controls.h"
#include "controls.h"
#include "diagnostics.h"
#include "health.h"
#include "plugin-settings.h"
void lenslink_frontend_init(void);
void lenslink_frontend_shutdown(void);
}

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace {

constexpr int MAX_SOURCES = 16;
constexpr char DOCK_ID[] = "lenslink_health";
constexpr char CONTROLS_DOCK_ID[] = "lenslink_controls";

/* Runtime-resolved frontend API (see file comment). */
struct FrontendApi {
	void (*add_event_callback)(obs_frontend_event_cb, void *);
	void (*remove_event_callback)(obs_frontend_event_cb, void *);
	void *(*get_main_window)(void);
	bool (*add_dock_by_id)(const char *, const char *, void *);
	void (*remove_dock)(const char *);
	void (*add_tools_menu_item)(const char *, obs_frontend_cb, void *);
};

FrontendApi api = {};
bool callback_installed = false;

template<typename T> void resolve(T &fn, const char *name)
{
#ifdef _WIN32
	HMODULE module = GetModuleHandleA("obs-frontend-api.dll");
	fn = module ? reinterpret_cast<T>(
			      GetProcAddress(module, name))
		    : nullptr;
#else
	fn = reinterpret_cast<T>(dlsym(RTLD_DEFAULT, name));
#endif
}

QLabel *status_label = nullptr;
QLabel *dock_label = nullptr; /* owned by OBS once the dock is added */
QTimer *timer = nullptr;

class FramePad : public QWidget {
public:
	std::function<void(double, double)> on_move;
	double zoom = 1.0;
	double cx = 0.5;
	double cy = 0.5;
	bool dragging = false;

	FramePad()
	{
		setMinimumHeight(72);
		setCursor(Qt::OpenHandCursor);
	}

	QSize sizeHint() const override { return QSize(200, 112); }

	void set_window(double z, double x, double y)
	{
		zoom = z;
		cx = x;
		cy = y;
		update();
	}

protected:
	void paintEvent(QPaintEvent *) override
	{
		QPainter p(this);
		p.fillRect(rect(), QColor(255, 255, 255, 20));
		double w = width() / zoom;
		double h = height() / zoom;
		QRectF box(cx * width() - w / 2, cy * height() - h / 2, w, h);
		p.setBrush(QColor(61, 123, 255, 60));
		p.setPen(QPen(QColor(61, 123, 255), 2));
		p.drawRoundedRect(box.adjusted(1, 1, -1, -1), 4, 4);
	}

	void mousePressEvent(QMouseEvent *e) override
	{
		dragging = true;
		move_to(e->position());
	}

	void mouseMoveEvent(QMouseEvent *e) override
	{
		if (dragging)
			move_to(e->position());
	}

	void mouseReleaseEvent(QMouseEvent *) override { dragging = false; }

private:
	void move_to(QPointF at)
	{
		double half = 0.5 / zoom;
		cx = qBound(half, at.x() / width(), 1.0 - half);
		cy = qBound(half, at.y() / height(), 1.0 - half);
		update();
		if (on_move)
			on_move(cx, cy);
	}
};

struct Controls {
	QWidget *root = nullptr;
	QComboBox *source = nullptr;
	QLabel *note = nullptr;
	QWidget *body = nullptr;
	QSlider *zoom = nullptr;
	QLabel *zoom_value = nullptr;
	QWidget *zoom_row = nullptr;
	QComboBox *lens = nullptr;
	QWidget *lens_row = nullptr;
	QPushButton *flash = nullptr;
	QSlider *rf_zoom = nullptr;
	QLabel *rf_value = nullptr;
	FramePad *pad = nullptr;
	QWidget *rf_box = nullptr;
	QCheckBox *hq = nullptr;
	QCheckBox *gs = nullptr;
	QComboBox *stab = nullptr;
	QWidget *stab_row = nullptr;
	QComboBox *res = nullptr;
	QComboBox *fps = nullptr;
	QComboBox *codec = nullptr;
	QWidget *format_row = nullptr;
	qint64 touched = 0;
	lenslink_ctl_state state = {};
} ctl;

QString num(double v, int digits)
{
	return QString::number(v, 'f', digits);
}

void ctl_send(const QString &json)
{
	if (!ctl.source || ctl.source->currentIndex() < 0)
		return;
	ctl.touched = QDateTime::currentMSecsSinceEpoch();
	QByteArray name = ctl.source->currentData().toString().toUtf8();
	lenslink_source_send(name.constData(), json.toUtf8().constData());
}

void ctl_send_reframe()
{
	ctl_send(QStringLiteral("{\"cmd\":\"reframe\",\"zoom\":%1,\"x\":%2,\"y\":%3}")
			 .arg(num(ctl.rf_zoom->value() / 10.0, 2),
			      num(ctl.pad->cx, 3), num(ctl.pad->cy, 3)));
}

QWidget *labelled(const char *key, QWidget *field, QWidget *parent)
{
	auto *row = new QWidget(parent);
	auto *layout = new QHBoxLayout(row);
	layout->setContentsMargins(0, 0, 0, 0);
	auto *label = new QLabel(QString::fromUtf8(obs_module_text(key)), row);
	label->setMinimumWidth(84);
	layout->addWidget(label);
	layout->addWidget(field, 1);
	return row;
}

QWidget *build_controls()
{
	auto *root = new QWidget;
	ctl.root = root;
	auto *outer = new QVBoxLayout(root);
	outer->setContentsMargins(10, 8, 10, 8);

	ctl.source = new QComboBox(root);
	outer->addWidget(ctl.source);
	ctl.note = new QLabel(root);
	ctl.note->setWordWrap(true);
	ctl.note->setStyleSheet(QStringLiteral("color: gray;"));
	outer->addWidget(ctl.note);

	ctl.body = new QWidget(root);
	auto *body = new QVBoxLayout(ctl.body);
	body->setContentsMargins(0, 0, 0, 0);
	outer->addWidget(ctl.body);

	ctl.zoom = new QSlider(Qt::Horizontal, ctl.body);
	ctl.zoom_value = new QLabel(ctl.body);
	ctl.zoom_value->setMinimumWidth(40);
	auto *zoom_field = new QWidget(ctl.body);
	auto *zoom_layout = new QHBoxLayout(zoom_field);
	zoom_layout->setContentsMargins(0, 0, 0, 0);
	zoom_layout->addWidget(ctl.zoom, 1);
	zoom_layout->addWidget(ctl.zoom_value);
	ctl.zoom_row = labelled("Web.Zoom", zoom_field, ctl.body);
	body->addWidget(ctl.zoom_row);
	QObject::connect(ctl.zoom, &QSlider::valueChanged, [](int v) {
		ctl.zoom_value->setText(num(v / 10.0, 1) + QStringLiteral("×"));
		ctl_send(QStringLiteral("{\"cmd\":\"zoom\",\"value\":%1}")
				 .arg(num(v / 10.0, 2)));
	});

	ctl.lens = new QComboBox(ctl.body);
	ctl.lens_row = labelled("Web.Lens", ctl.lens, ctl.body);
	body->addWidget(ctl.lens_row);
	QObject::connect(ctl.lens, &QComboBox::activated, [](int i) {
		QJsonObject cmd;
		cmd["cmd"] = "selectLens";
		cmd["label"] = ctl.lens->itemData(i).toString();
		ctl_send(QString::fromUtf8(
			QJsonDocument(cmd).toJson(QJsonDocument::Compact)));
	});

	auto *buttons = new QWidget(ctl.body);
	auto *buttons_layout = new QHBoxLayout(buttons);
	buttons_layout->setContentsMargins(0, 0, 0, 0);
	ctl.flash = new QPushButton(QString::fromUtf8(obs_module_text("Web.Flashlight")),
				    buttons);
	ctl.flash->setCheckable(true);
	auto *flip = new QPushButton(QString::fromUtf8(obs_module_text("Web.Flip")),
				     buttons);
	buttons_layout->addWidget(ctl.flash);
	buttons_layout->addWidget(flip);
	body->addWidget(buttons);
	QObject::connect(ctl.flash, &QPushButton::clicked, [](bool on) {
		ctl_send(QStringLiteral("{\"cmd\":\"flashlight\",\"on\":%1}")
				 .arg(on ? "true" : "false"));
	});
	QObject::connect(flip, &QPushButton::clicked,
			 [] { ctl_send(QStringLiteral("{\"cmd\":\"flip\"}")); });

	ctl.rf_box = new QWidget(ctl.body);
	auto *rf = new QVBoxLayout(ctl.rf_box);
	rf->setContentsMargins(0, 0, 0, 0);
	ctl.rf_zoom = new QSlider(Qt::Horizontal, ctl.rf_box);
	ctl.rf_zoom->setRange(10, 40);
	ctl.rf_value = new QLabel(ctl.rf_box);
	ctl.rf_value->setMinimumWidth(40);
	auto *rf_field = new QWidget(ctl.rf_box);
	auto *rf_layout = new QHBoxLayout(rf_field);
	rf_layout->setContentsMargins(0, 0, 0, 0);
	rf_layout->addWidget(ctl.rf_zoom, 1);
	rf_layout->addWidget(ctl.rf_value);
	rf->addWidget(labelled("Web.Reframe", rf_field, ctl.rf_box));
	ctl.pad = new FramePad;
	ctl.pad->setParent(ctl.rf_box);
	ctl.pad->setToolTip(QString::fromUtf8(obs_module_text("Web.Reframe.Pad")));
	rf->addWidget(ctl.pad);
	ctl.hq = new QCheckBox(QString::fromUtf8(obs_module_text("Web.Reframe.HQ")),
			       ctl.rf_box);
	ctl.hq->setToolTip(QString::fromUtf8(obs_module_text("Web.Reframe.HQ.Tip")));
	rf->addWidget(ctl.hq);
	body->addWidget(ctl.rf_box);
	QObject::connect(ctl.rf_zoom, &QSlider::valueChanged, [](int v) {
		ctl.rf_value->setText(num(v / 10.0, 1) + QStringLiteral("×"));
		double half = 0.5 / (v / 10.0);
		ctl.pad->set_window(v / 10.0, qBound(half, ctl.pad->cx, 1.0 - half),
				    qBound(half, ctl.pad->cy, 1.0 - half));
		ctl_send_reframe();
	});
	ctl.pad->on_move = [](double, double) { ctl_send_reframe(); };
	QObject::connect(ctl.hq, &QCheckBox::clicked, [](bool on) {
		ctl_send(QStringLiteral("{\"cmd\":\"reframe\",\"hq\":%1}")
				 .arg(on ? "true" : "false"));
	});

	ctl.gs = new QCheckBox(QString::fromUtf8(obs_module_text("Web.GreenScreen")),
			       ctl.body);
	body->addWidget(ctl.gs);
	QObject::connect(ctl.gs, &QCheckBox::clicked, [](bool on) {
		ctl_send(QStringLiteral("{\"cmd\":\"green_screen\",\"on\":%1}")
				 .arg(on ? "true" : "false"));
	});

	ctl.stab = new QComboBox(ctl.body);
	ctl.stab->addItem(QString::fromUtf8(obs_module_text("Web.Stabilization.Off")),
			  QStringLiteral("off"));
	ctl.stab->addItem(
		QString::fromUtf8(obs_module_text("Web.Stabilization.Standard")),
		QStringLiteral("standard"));
	ctl.stab->addItem(
		QString::fromUtf8(obs_module_text("Web.Stabilization.Cinematic")),
		QStringLiteral("cinematic"));
	ctl.stab_row = labelled("Web.Stabilization", ctl.stab, ctl.body);
	body->addWidget(ctl.stab_row);
	QObject::connect(ctl.stab, &QComboBox::activated, [](int i) {
		ctl_send(QStringLiteral("{\"cmd\":\"stabilization\",\"mode\":\"%1\"}")
				 .arg(ctl.stab->itemData(i).toString()));
	});

	ctl.format_row = new QWidget(ctl.body);
	auto *format = new QHBoxLayout(ctl.format_row);
	format->setContentsMargins(0, 0, 0, 0);
	ctl.res = new QComboBox(ctl.format_row);
	ctl.fps = new QComboBox(ctl.format_row);
	ctl.codec = new QComboBox(ctl.format_row);
	format->addWidget(ctl.res);
	format->addWidget(ctl.fps);
	format->addWidget(ctl.codec);
	body->addWidget(ctl.format_row);
	QObject::connect(ctl.res, &QComboBox::activated, [](int i) {
		ctl_send(QStringLiteral("{\"cmd\":\"set_format\",\"resolution\":\"%1\"}")
				 .arg(ctl.res->itemText(i)));
	});
	QObject::connect(ctl.fps, &QComboBox::activated, [](int i) {
		ctl_send(QStringLiteral("{\"cmd\":\"set_format\",\"fps\":%1}")
				 .arg(ctl.fps->itemData(i).toInt()));
	});
	QObject::connect(ctl.codec, &QComboBox::activated, [](int i) {
		ctl_send(QStringLiteral("{\"cmd\":\"set_format\",\"codec\":\"%1\"}")
				 .arg(ctl.codec->itemData(i).toString()));
	});

	outer->addStretch(1);
	return root;
}

void fill_combo(QComboBox *box, const QStringList &labels,
		const QVariantList &values, const QVariant &current)
{
	QSignalBlocker block(box);
	bool same = box->count() == labels.size();
	for (int i = 0; same && i < labels.size(); i++)
		same = box->itemData(i) == values[i];
	if (!same) {
		box->clear();
		for (int i = 0; i < labels.size(); i++)
			box->addItem(labels[i], values[i]);
	}
	box->setCurrentIndex(box->findData(current));
}

void refresh_controls(const lenslink_health *list, size_t count)
{
	if (!ctl.source)
		return;

	QStringList names;
	for (size_t i = 0; i < count; i++)
		if (!list[i].is_screen)
			names << QString::fromUtf8(list[i].source_name);
	{
		QSignalBlocker block(ctl.source);
		QString keep = ctl.source->currentData().toString();
		bool same = ctl.source->count() == names.size();
		for (int i = 0; same && i < names.size(); i++)
			same = ctl.source->itemData(i).toString() == names[i];
		if (!same) {
			ctl.source->clear();
			for (const QString &n : names)
				ctl.source->addItem(n, n);
			int at = ctl.source->findData(keep);
			ctl.source->setCurrentIndex(at >= 0 ? at : 0);
		}
	}
	ctl.source->setVisible(names.size() > 1);

	if (names.isEmpty()) {
		ctl.body->setVisible(false);
		ctl.note->setText(QString::fromUtf8(obs_module_text("ControlsDock.Empty")));
		return;
	}

	char json[2048];
	QByteArray name = ctl.source->currentData().toString().toUtf8();
	lenslink_ctl_state st;
	if (!lenslink_source_state(name.constData(), json, sizeof(json)) ||
	    !lenslink_ctl_parse(json, strlen(json), &st) || st.lens_count == 0) {
		ctl.body->setVisible(false);
		ctl.note->setText(QString::fromUtf8(obs_module_text("Controls.NotConnected")));
		return;
	}
	ctl.note->clear();
	ctl.body->setVisible(true);

	if (QDateTime::currentMSecsSinceEpoch() - ctl.touched < 1500 ||
	    ctl.pad->dragging || ctl.zoom->isSliderDown() ||
	    ctl.rf_zoom->isSliderDown())
		return;

	{
		QSignalBlocker block(ctl.zoom);
		ctl.zoom_row->setVisible(st.max_zoom > 1.0);
		ctl.zoom->setRange(10, qRound(st.max_zoom * 10));
		ctl.zoom->setValue(qRound(st.zoom * 10));
		ctl.zoom_value->setText(num(st.zoom, 1) + QStringLiteral("×"));
	}

	QStringList labels;
	QVariantList values;
	for (int i = 0; i < st.lens_count; i++) {
		labels << QString::fromUtf8(lenslink_lens_text(st.lenses[i]));
		values << QString::fromUtf8(st.lenses[i]);
	}
	ctl.lens_row->setVisible(st.lens_count > 1);
	fill_combo(ctl.lens, labels, values, QString::fromUtf8(st.lens));

	ctl.flash->setVisible(st.has_flashlight);
	{
		QSignalBlocker block(ctl.flash);
		ctl.flash->setChecked(st.flashlight);
	}

	ctl.stab_row->setVisible(st.stabilization[0] != 0);
	{
		QSignalBlocker block(ctl.stab);
		ctl.stab->setCurrentIndex(
			ctl.stab->findData(QString::fromUtf8(st.stabilization)));
	}

	ctl.rf_box->setVisible(st.supports_reframe);
	{
		QSignalBlocker block(ctl.rf_zoom);
		ctl.rf_zoom->setValue(qRound(st.reframe_zoom * 10));
		ctl.rf_value->setText(num(st.reframe_zoom, 1) + QStringLiteral("×"));
		ctl.pad->set_window(st.reframe_zoom, st.reframe_x, st.reframe_y);
		ctl.pad->setVisible(st.reframe_zoom > 1.01);
	}
	ctl.hq->setVisible(st.supports_reframe_hq || st.reframe_hq);
	{
		QSignalBlocker block(ctl.hq);
		ctl.hq->setChecked(st.reframe_hq);
	}

	ctl.gs->setVisible(st.supports_green_screen);
	{
		QSignalBlocker block(ctl.gs);
		ctl.gs->setChecked(st.green_screen);
	}

	bool formats = st.resolution_count > 0 && st.frame_rate_count > 0;
	ctl.format_row->setVisible(formats);
	if (formats) {
		QStringList res;
		QVariantList res_values;
		for (int i = 0; i < st.resolution_count; i++) {
			res << QString::fromUtf8(st.resolutions[i]);
			res_values << QString::fromUtf8(st.resolutions[i]);
		}
		fill_combo(ctl.res, res, res_values, QString::fromUtf8(st.resolution));
		QStringList fps;
		QVariantList fps_values;
		for (int i = 0; i < st.frame_rate_count; i++) {
			fps << QStringLiteral("%1 fps").arg(st.frame_rates[i]);
			fps_values << st.frame_rates[i];
		}
		fill_combo(ctl.fps, fps, fps_values, st.fps);
		QStringList codecs;
		QVariantList codec_values;
		for (int i = 0; i < st.codec_count; i++) {
			QString c = QString::fromUtf8(st.codecs[i]);
			codecs << (c == QStringLiteral("hevc") ? QStringLiteral("HEVC")
				   : c == QStringLiteral("h264") ? QStringLiteral("H.264")
								 : c);
			codec_values << c;
		}
		ctl.codec->setVisible(st.codec_count > 1);
		fill_combo(ctl.codec, codecs, codec_values,
			   QString::fromUtf8(st.codec));
	}
}

/* Rate derivation: previous cumulative counters per source name. */
struct PrevSample {
	uint64_t frames;
	uint64_t bytes;
	uint64_t time_ns;
	double fps;
	QString text;
};
std::unordered_map<std::string, PrevSample> previous;

PrevSample next_sample(const lenslink_health &h, const PrevSample *prev)
{
	if (prev && h.sample_ns == prev->time_ns)
		return *prev;

	PrevSample s = {h.frames, h.bytes, h.sample_ns, 0.0,
			QStringLiteral("…")};
	if (!prev || !prev->time_ns || h.sample_ns < prev->time_ns ||
	    h.frames < prev->frames)
		return s;

	double seconds = double(h.sample_ns - prev->time_ns) / 1e9;
	double fps = double(h.frames - prev->frames) / seconds;
	double mbps = double(h.bytes - prev->bytes) * 8.0 / seconds / 1e6;
	s.fps = prev->fps > 0.0 ? (prev->fps + fps) / 2.0 : fps;

	s.text = QStringLiteral("%1 fps · %2 Mb/s")
			 .arg(qRound(s.fps))
			 .arg(mbps, 0, 'f', 1);
	if (h.latency_ms > 0)
		s.text += QStringLiteral(" · %1 ms").arg(h.latency_ms);
	return s;
}

void refresh()
{
	if (!status_label)
		return;

	lenslink_health list[MAX_SOURCES];
	size_t count = lenslink_health_enum(list, MAX_SOURCES);

	QStringList bar_parts;
	QStringList dock_rows;
	std::unordered_map<std::string, PrevSample> next;
	int standby_count = 0;
	int unarmed_count = 0;

	for (size_t i = 0; i < count; i++) {
		const lenslink_health &h = list[i];
		std::string key = h.source_name;
		const PrevSample *prev = nullptr;
		auto it = previous.find(key);
		if (it != previous.end())
			prev = &it->second;
		next[key] = next_sample(h, prev);
		QString rates = next[key].text;

		QString who = QString::fromUtf8(
			h.device[0] ? h.device : h.source_name);
		if (h.connected && !h.standby) {
			bar_parts << QStringLiteral("%1 %2").arg(
				who, rates);
		} else if (h.connected && h.unarmed) {
			unarmed_count++;
		} else if (h.connected && h.standby) {
			standby_count++;
		}

		/* Dock: every source gets a row, live or not. */
		QString detail;
		if (h.connected && !h.standby)
			detail = rates;
		else
			detail = QString::fromUtf8(h.status).toHtmlEscaped();
		dock_rows << QStringLiteral("<b>%1</b>%2<br/>%3")
				     .arg(QString::fromUtf8(h.source_name)
						  .toHtmlEscaped(),
					  h.device[0] ? QStringLiteral(
							      " — %1")
							      .arg(QString::fromUtf8(
									   h.device)
									   .toHtmlEscaped())
						      : QString(),
					  detail);
	}
	previous = std::move(next);

	/* Status bar: live streams get numbers; standby-only gets a word;
	 * nothing LensLink → no label at all (don't crowd OBS's bar). */
	QString prefix = QString::fromUtf8(obs_module_text("StatusBar.Label"));
	if (!bar_parts.isEmpty()) {
		status_label->setText(QStringLiteral("%1 %2").arg(
			prefix, bar_parts.join(QStringLiteral("  |  "))));
		status_label->setVisible(true);
	} else if (standby_count > 0) {
		status_label->setText(QStringLiteral("%1 %2").arg(
			prefix, QString::fromUtf8(
					obs_module_text("StatusBar.Standby"))));
		status_label->setVisible(true);
	} else if (unarmed_count > 0) {
		status_label->setText(QStringLiteral("%1 %2").arg(
			prefix, QString::fromUtf8(
					obs_module_text("StatusBar.NotArmed"))));
		status_label->setVisible(true);
	} else {
		status_label->setVisible(false);
	}

	refresh_controls(list, count);

	if (dock_label) {
		dock_label->setText(
			dock_rows.isEmpty()
				? QStringLiteral("<i>%1</i>")
					  .arg(QString::fromUtf8(obs_module_text(
							       "HealthDock.Empty"))
						       .toHtmlEscaped())
				: dock_rows.join(
					  QStringLiteral("<br/><br/>")));
	}
}

void create_widgets()
{
	auto *window =
		static_cast<QMainWindow *>(api.get_main_window());
	if (!window || status_label)
		return;

	status_label = new QLabel(window);
	status_label->setVisible(false);
	window->statusBar()->addPermanentWidget(status_label);

	if (api.add_dock_by_id) {
		dock_label = new QLabel;
		dock_label->setTextFormat(Qt::RichText);
		dock_label->setAlignment(Qt::AlignTop | Qt::AlignLeft);
		dock_label->setWordWrap(true);
		dock_label->setContentsMargins(10, 8, 10, 8);
		if (!api.add_dock_by_id(DOCK_ID,
					obs_module_text("HealthDock"),
					dock_label)) {
			delete dock_label;
			dock_label = nullptr;
		}
	}

	if (api.add_dock_by_id) {
		QWidget *controls = build_controls();
		if (!api.add_dock_by_id(CONTROLS_DOCK_ID,
					obs_module_text("ControlsDock"),
					controls)) {
			delete controls;
			ctl = Controls();
		}
	}

	timer = new QTimer(window);
	QObject::connect(timer, &QTimer::timeout, [] { refresh(); });
	timer->start(1000);

	blog(LOG_INFO, "[lenslink] frontend UI ready (status bar%s)",
	     dock_label ? " + dock" : "");
}

void destroy_widgets()
{
	if (timer) {
		timer->stop();
		timer->deleteLater();
		timer = nullptr;
	}
	if (status_label) {
		auto *window = static_cast<QMainWindow *>(
			api.get_main_window());
		if (window)
			window->statusBar()->removeWidget(status_label);
		status_label->deleteLater();
		status_label = nullptr;
	}
	if (dock_label) {
		/* OBS owns the widget; removing the dock destroys it. */
		if (api.remove_dock)
			api.remove_dock(DOCK_ID);
		dock_label = nullptr;
	}
	if (ctl.root) {
		if (api.remove_dock)
			api.remove_dock(CONTROLS_DOCK_ID);
		ctl = Controls();
	}
	previous.clear();
}

/* Tools -> "LensLink Settings": the plugin-wide switches that never made
 * sense per source. Modal, plain widgets, no moc. */
void show_settings_dialog(void *)
{
	QMainWindow *window =
		static_cast<QMainWindow *>(api.get_main_window());
	QDialog dialog(window);
	dialog.setWindowTitle(obs_module_text("Settings.Title"));

	auto *layout = new QVBoxLayout(&dialog);

	auto *gpu = new QCheckBox(obs_module_text("Settings.GpuPipeline"),
				  &dialog);
	auto *gpu_note =
		new QLabel(obs_module_text("Settings.GpuPipeline.Note"),
			   &dialog);
	gpu_note->setWordWrap(true);
	gpu_note->setStyleSheet(QStringLiteral("color: gray;"));

	auto *web = new QCheckBox(obs_module_text("Settings.Web"), &dialog);
	auto *port = new QSpinBox(&dialog);
	port->setRange(1024, 65535);
	auto *diag = new QCheckBox(obs_module_text("Settings.Diagnostics"),
				   &dialog);
	auto *dump = new QCheckBox(obs_module_text("Settings.Dump"), &dialog);
	auto *bench = new QCheckBox(obs_module_text("Settings.Benchmark"),
				    &dialog);
	bench->setToolTip(obs_module_text("Settings.Benchmark.Tip"));

	obs_data_t *current = lenslink_settings_snapshot();
	gpu->setChecked(obs_data_get_bool(current, LLS_GPU_PIPELINE));
	web->setChecked(obs_data_get_bool(current, LLS_WEB_ENABLED));
	port->setValue((int)obs_data_get_int(current, LLS_WEB_PORT));
	diag->setChecked(obs_data_get_bool(current, LLS_DIAGNOSTICS));
	dump->setChecked(obs_data_get_bool(current, LLS_DUMP_STREAM));
	bench->setChecked(obs_data_get_bool(current, LLS_BENCHMARK));
	obs_data_release(current);

	layout->addWidget(gpu);
	layout->addWidget(gpu_note);
	layout->addSpacing(12);
	layout->addWidget(web);
	auto *form = new QFormLayout();
	form->addRow(obs_module_text("Settings.WebPort"), port);
	layout->addLayout(form);
	layout->addSpacing(12);
	layout->addWidget(diag);
	layout->addWidget(dump);
	layout->addWidget(bench);

	/* Version footer, mirroring the source-properties one. */
	auto *version = new QLabel(
		QStringLiteral("LensLink " LENSLINK_VERSION), &dialog);
	version->setStyleSheet(
		QStringLiteral("color: gray; font-size: 11px;"));
	layout->addSpacing(8);
	layout->addWidget(version);

	/* Diagnostics is an action, not a setting, so it applies whether or
	 * not the dialog is accepted: the report describes the state the
	 * reporter is in right now. */
	auto *diagbtn = new QPushButton(
		obs_module_text("Settings.CopyDiagnostics"), &dialog);
	auto *diagnote = new QLabel(&dialog);
	diagnote->setWordWrap(true);
	diagnote->setStyleSheet(QStringLiteral("color: gray;"));
	QObject::connect(diagbtn, &QPushButton::clicked, [diagnote]() {
		char *report = lenslink_diagnostics_report();
		QGuiApplication::clipboard()->setText(
			QString::fromUtf8(report));
		bfree(report);
		lenslink_diagnostics_log();
		diagnote->setText(
			obs_module_text("Settings.CopyDiagnostics.Done"));
	});
	layout->addSpacing(12);
	layout->addWidget(diagbtn);
	layout->addWidget(diagnote);

	auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok |
						     QDialogButtonBox::Cancel,
					     &dialog);
	QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog,
			 &QDialog::accept);
	QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog,
			 &QDialog::reject);
	layout->addWidget(buttons);

	if (dialog.exec() != QDialog::Accepted)
		return;

	obs_data_t *values = obs_data_create();
	obs_data_set_bool(values, LLS_GPU_PIPELINE, gpu->isChecked());
	obs_data_set_bool(values, LLS_WEB_ENABLED, web->isChecked());
	obs_data_set_int(values, LLS_WEB_PORT, port->value());
	obs_data_set_bool(values, LLS_DIAGNOSTICS, diag->isChecked());
	obs_data_set_bool(values, LLS_DUMP_STREAM, dump->isChecked());
	obs_data_set_bool(values, LLS_BENCHMARK, bench->isChecked());
	lenslink_settings_update(values);
	obs_data_release(values);

	/* Web/diagnostics apply immediately; the pipeline switch waits for
	 * the restart the note promised. */
	ios_camera_apply_global_settings();
}

void frontend_event(enum obs_frontend_event event, void *)
{
	switch (event) {
	case OBS_FRONTEND_EVENT_FINISHED_LOADING:
		create_widgets();
		break;
	case OBS_FRONTEND_EVENT_EXIT:
		destroy_widgets();
		break;
	default:
		break;
	}
}

} // namespace

void lenslink_frontend_init(void)
{
	resolve(api.add_event_callback, "obs_frontend_add_event_callback");
	resolve(api.remove_event_callback,
		"obs_frontend_remove_event_callback");
	resolve(api.get_main_window, "obs_frontend_get_main_window");
	resolve(api.add_dock_by_id, "obs_frontend_add_dock_by_id");
	resolve(api.remove_dock, "obs_frontend_remove_dock");
	resolve(api.add_tools_menu_item, "obs_frontend_add_tools_menu_item");

	if (!api.add_event_callback || !api.remove_event_callback ||
	    !api.get_main_window) {
		blog(LOG_INFO,
		     "[lenslink] no OBS frontend in this process — "
		     "status-bar/dock UI disabled");
		return;
	}

	api.add_event_callback(frontend_event, nullptr);
	callback_installed = true;

	if (api.add_tools_menu_item)
		api.add_tools_menu_item(obs_module_text("Settings.MenuItem"),
					show_settings_dialog, nullptr);
}

void lenslink_frontend_shutdown(void)
{
	if (callback_installed) {
		api.remove_event_callback(frontend_event, nullptr);
		callback_installed = false;
	}
	/* Widgets are torn down on OBS_FRONTEND_EVENT_EXIT, which precedes
	 * module unload; nothing further to do here. */
}
