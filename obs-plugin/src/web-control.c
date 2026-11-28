#include <obs-module.h>
#include <util/threading.h>
#include <util/platform.h>
#include <util/bmem.h>
#include <util/dstr.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>

#include "net-compat.h"
#include "web-control.h"
#include "web-auth.h"
#include "plugin-settings.h"
#include "diagnostics.h"
#include "json-reader.h"

#define MAX_REQUEST (16 * 1024)
#define MAX_CONTROL_BODY 512
#define REQUEST_DEADLINE_NS (3ULL * 1000000000ULL)

/*
 * Browser control panel, styled to docs/UI_DESIGN.md (shared palette,
 * control metaphors and ordering with the app's Live panel). Single-quoted
 * HTML/SVG attributes keep the C escaping sane.
 */
static const char *const web_text_keys[] = {
	"Web.Title",
	"Web.Connecting",
	"Web.Idle",
	"Web.NoSources",
	"Web.Unreachable",
	"Web.Recalibrate",
	"Web.Sync.Measuring",
	"Web.Sync.Locked",
	"Web.Sync.Relocking",
	"Web.ScreenNote",
	"Web.StartCamera",
	"Web.StopCamera",
	"Web.AutoStart",
	"Web.AutoStart.Tip",
	"Web.StartHint",
	"Web.NotArmedHint",
	"Web.Pause",
	"Web.Resume",
	"Web.Shutter",
	"Web.NaturalBlur",
	"Web.NaturalBlur.Tip",
	"Web.Lock",
	"Web.Lock.Tip",
	"Web.Focus",
	"Web.WB",
	"Web.Calibrate",
	"Web.Calibrate.Tip",
	"Web.Calibrate.Pick",
	"Web.Calibrate.NoPicture",
	"Web.GreenScreen",
	"Web.Blur",
	"Web.Blur.Off",
	"Web.Blur.Depth",
	"Web.Blur.Cinematic",
	"Web.All",
	"Web.Mic",
	"Web.PhoneMic",
	"Web.Flashlight",
	"Web.FlashlightFull.Tip",
	"Web.Flip",
	"Web.Resolution",
	"Web.FrameRate",
	"Web.Codec",
	"Web.Zoom",
	"Web.Lens",
	"Web.SubjectAuto.Tip",
	"Web.Auto",
	"Web.Subject",
	"Web.Stabilization",
	"Web.Stabilization.Off",
	"Web.Stabilization.Standard",
	"Web.Stabilization.Cinematic",
	"Web.AntiFlicker",
	"Web.Bitrate",
	"Web.Bitrate.Stable",
	"Web.Bitrate.Maximum",
	"Web.Reframe",
	"Web.Reframe.Tip",
	"Web.Reframe.Pad",
	"Web.Reframe.HQ",
	"Web.Reframe.HQ.Tip",
	"Web.Lens.Front",
	"Web.Lens.FrontUltraWide",
	"Web.Lens.MainWide",
	"Web.Lens.UltraWide",
	"Web.Lens.Telephoto",
	"Web.Tint",
	"Web.Color",
	"Web.Color.SDR",
	"Web.Color.HLG",
	"Web.Color.Log",
	"Web.Guides",
	"Web.Guides.Off",
	"Web.Guides.Grid",
	"Web.Pro",
	"Web.Pro.Tip",
	"Web.Latency",
	"Web.Battery",
	"Web.FocusA",
	"Web.FocusB",
	"Web.FocusPull",
	"Web.Shortcuts",
};

#define WEB_KEY_PREFIX "Web."

static const char control_page[] =
	"<meta name='viewport' content='width=device-width,initial-scale=1'>"
	"<title data-t='Title'></title><style>"
	/* color-scheme makes the browser's own chrome — most visibly the
	 * native dropdown popup of a <select> — render dark; without it the
	 * popup was a light list inheriting white text (invisible until
	 * hovered). The explicit option colors cover browsers that style
	 * options directly instead. */
	":root{color-scheme:dark;--accent:#3D7BFF;--live:#30D158;--amber:#FF9F0A;"
	"--red:#FF453A;--grey:#8E8E93;--bg:#000;--glass:#161616;"
	"--hair:rgba(255,255,255,0.08);--txt:#fff;--txt2:rgba(235,235,245,0.6);"
	"--yellow:#FFD60A;--box:rgba(0,0,0,.5);--boxsel:rgba(0,0,0,.75)}"
	"option{background:#161616;color:#fff}"
	"*{box-sizing:border-box}"
	"body{font-family:system-ui,-apple-system,sans-serif;background:var(--bg);"
	"color:var(--txt);max-width:440px;margin:0 auto;padding:20px 16px}"
	/* Wraps so the sync pill drops below the status pill on a narrow
	 * phone screen instead of squeezing either one. */
	"header{display:flex;align-items:center;justify-content:space-between;"
	"gap:8px;flex-wrap:wrap;margin-bottom:16px}"
	"h1{font-size:20px;font-weight:600;margin:0}"
	".pill{display:inline-flex;align-items:center;gap:8px;background:var(--glass);"
	"border:1px solid var(--hair);border-radius:999px;padding:6px 12px;"
	"font-size:13px;font-weight:600}"
	".dot{width:10px;height:10px;border-radius:50%;background:var(--grey);"
	"transition:background .2s}"
	".panel{background:var(--glass);border:1px solid var(--hair);"
	"border-radius:16px;padding:16px;backdrop-filter:blur(20px)}"
	".row{display:flex;align-items:center;gap:12px;margin:14px 0}"
	".row:first-child{margin-top:0}"
	".ro{font-variant-numeric:tabular-nums;font-family:ui-monospace,monospace;"
	"width:48px;text-align:right;font-size:13px;flex:none}"
	"input[type=range]{flex:1;min-width:0;accent-color:var(--accent);height:4px}"
	".ic{width:18px;height:18px;flex:none;color:var(--txt2)}"
	".seg{display:inline-flex;background:rgba(255,255,255,.1);border-radius:12px;"
	"padding:2px;flex:none}.seg button{background:none;border:0;color:var(--txt);"
	"padding:6px 14px;border-radius:10px;font-size:13px;cursor:pointer}"
	".seg button.on{background:var(--accent)}"
	".hint{color:var(--txt2);font-size:13px;flex:1}"
	".chip{width:44px;height:44px;border:0;border-radius:50%;"
	"background:rgba(255,255,255,.12);color:var(--txt);cursor:pointer;"
	"display:inline-flex;align-items:center;justify-content:center}"
	".chip.on{background:var(--accent)}.chip .ic{color:var(--txt);width:20px;height:20px}"
	".chip:disabled{opacity:.4;cursor:default}"
	".chip.on .lk-open,.chip:not(.on) .lk-shut{display:none}"
	"input.y{accent-color:var(--yellow)}.ro.y{color:var(--yellow)}"
	".lenses{display:flex;justify-content:center;align-items:center;gap:8px}"
	".lensbtns{display:flex;align-items:center;gap:8px}"
	".lb{width:34px;height:34px;padding:0;border:0;border-radius:50%;"
	"background:rgba(0,0,0,.45);color:var(--txt);font-size:11px;font-weight:700;"
	"font-variant-numeric:tabular-nums;cursor:pointer}"
	".lb.on{width:40px;height:40px;font-size:13px;color:var(--yellow);"
	"background:rgba(0,0,0,.6)}"
	".lenses select{flex:none;width:auto}"
	".lenses .chip{margin-left:8px}.lenses #fl{margin:0 8px 0 0}"
	".sep{height:1px;background:var(--hair);margin:14px -16px}"
	".tchips{display:flex;gap:6px}"
	".tc{flex:1;min-width:0;position:relative;height:30px;padding:0 4px;border:0;"
	"border-radius:999px;background:rgba(255,255,255,.12);"
	"color:rgba(255,255,255,.8);font-size:12px;font-weight:600;cursor:pointer;"
	"white-space:nowrap}"
	".tc.on{background:#fff;color:#000}"
	".tc .a{position:absolute;top:-5px;right:-2px;width:14px;height:14px;"
	"border-radius:50%;background:var(--yellow);color:#000;font-size:8px;"
	"font-weight:800;line-height:14px;text-align:center}"
	".tc.on .a{background:#000;color:var(--yellow)}"
	".dial{display:flex;flex-direction:column;align-items:center;gap:6px;margin:12px 0}"
	".readout{color:var(--yellow);font-size:15px;font-weight:700;min-height:20px;"
	"font-variant-numeric:tabular-nums}"
	".dial input{width:100%}.dial input:disabled{opacity:.4}"
	".lights{position:relative;width:100%;height:16px;color:var(--txt2)}"
	".lights svg{position:absolute;top:0;width:14px;height:14px;"
	"transform:translateX(-50%)}"
	".still img{display:block;width:100%;border-radius:12px;cursor:crosshair;"
	"background:#000;margin-bottom:12px}"
	".pad{position:relative;aspect-ratio:16/9;margin:0 0 14px;border-radius:12px;"
	"background:rgba(255,255,255,.08);touch-action:none;cursor:grab;overflow:hidden}"
	".pad:focus-visible{outline:2px solid var(--accent)}"
	".pad img{position:absolute;inset:0;width:100%;height:100%;display:none;"
	"pointer-events:none;background:#000}.pad.bg img{display:block}"
	".pad div{position:absolute;border:2px solid var(--accent);border-radius:6px;"
	"background:rgba(255,255,255,.12);pointer-events:none}"
	".tools{display:flex;gap:10px;align-items:center;justify-content:flex-end}"
	".gap{width:44px;height:44px;flex:none}"
	"select{flex:1;min-width:0;background:rgba(255,255,255,.12);color:var(--txt);border:0;"
	"border-radius:12px;padding:0 12px;height:44px;font-size:14px}"
	"select:disabled{opacity:.4}"
	"#fmtrow{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}"
	".primary{width:100%;height:44px;border:0;border-radius:12px;"
	"background:var(--accent);color:#fff;font-size:15px;font-weight:600;"
	"cursor:pointer}"
	/* Stop is the one destructive control (docs/UI_DESIGN.md §1). */
	".primary.danger{background:var(--red)}"
	/* Two-button action rows; the auto-start toggle reads like a chip:
	 * grey when off, accent when on. */
	".btnrow{display:flex;gap:10px;margin-top:14px}"
	".btnrow:first-child{margin-top:0}"
	".primary.toggle{background:rgba(255,255,255,.12)}"
	".primary.toggle.on{background:var(--accent)}"
	".lbl{font-size:13px;color:var(--txt2);min-width:48px;white-space:nowrap;flex:none}"
	"button:focus-visible,select:focus-visible,input:focus-visible,"
	"[role=button]:focus-visible{outline:2px solid var(--accent);"
	"outline-offset:2px}"
	"#gsdv{cursor:pointer}"
	"button.pill{color:var(--txt);cursor:pointer}.pill.on{background:#fff;color:#000}"
	".info{width:24px;height:24px;padding:0;border:1.5px solid var(--txt2);"
	"border-radius:50%;background:none;color:var(--txt2);font-weight:700;cursor:pointer}"
	".tip{background:var(--glass);border-radius:12px;padding:10px 12px;"
	"font-size:13px;margin-bottom:12px}"
	".meter{flex:1;min-width:0;height:8px;border-radius:2px;"
	"background:rgba(255,255,255,.12);overflow:hidden}#meterfill{height:100%;width:0}"
	/* Pro: the phone's Pro overlay. Dark see-through boxes float on the
	 * latest still; values in monospace; buttons are equal boxes. */
	"body:not(.pro) .proonly,body:not(.pro) #gd{display:none!important}"
	".frame{position:relative;aspect-ratio:16/9;border-radius:12px;overflow:hidden;"
	"background:#000;margin-bottom:14px}"
	".frame img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}"
	".frame>div{position:absolute;left:6px;right:6px;display:grid;gap:3px}"
	".ptop{top:6px;grid-template-columns:1.3fr 1.3fr 1fr 1.6fr}"
	"button.bx{border:0;color:var(--txt);cursor:pointer}"
	".frame .tchips{bottom:6px;grid-auto-flow:column;grid-auto-columns:1fr}"
	".bx{background:var(--box);border-radius:6px;min-height:36px;padding:3px;"
	"display:flex;flex-direction:column;align-items:center;justify-content:center;"
	"font:600 12px ui-monospace,monospace;font-variant-numeric:tabular-nums;"
	"white-space:nowrap;overflow:hidden}"
	".bx small,.frame .tc{font:600 9px system-ui,sans-serif;color:var(--txt2)}"
	".ur{display:flex;align-items:baseline;gap:4px}"
	".tc .v{display:none}"
	".frame .tc{height:auto;min-height:36px;border-radius:6px;background:var(--box);"
	"display:flex;flex-direction:column;align-items:center;justify-content:center;padding:3px}"
	".frame .tc.on{background:var(--boxsel);color:var(--txt2);"
	"box-shadow:inset 0 0 0 1px rgba(255,255,255,.35)}"
	".frame .tc .v{display:block;font:600 12px ui-monospace,monospace;color:var(--txt);"
	"font-variant-numeric:tabular-nums}"
	".frame .tc .a{top:3px;right:3px;width:5px;height:5px;font-size:0;background:var(--accent)}"
	".frame .tc.on .a{background:var(--accent)}"
	".pmeters{display:flex;align-items:center;gap:10px;margin:12px 0;"
	"font:600 11px ui-monospace,monospace;font-variant-numeric:tabular-nums}"
	".bat{display:inline-block;width:20px;height:10px;border:1.5px solid var(--txt2);"
	"border-radius:3px;padding:1px}#batfill{height:100%;width:0;border-radius:1px}"
	"body.pro .panel{background:var(--bg);border:0;padding:0;backdrop-filter:none}"
	"body.pro .sep{margin:14px 0}"
	"body.pro .lb{background:var(--glass)}"
	".pmeters .lbl{font:600 10px system-ui,sans-serif}"
	"body.pro .tools,body.pro .btnrow{gap:3px}"
	"body.pro .tools .chip{flex:1;border-radius:6px;background:var(--glass)}"
	"body.pro .tools .chip.on{background:var(--glass);color:var(--yellow)}"
	"body.pro .tools .chip.on .ic{color:var(--yellow)}"
	"body.pro .tools .gap{display:none}"
	"body.pro .tools .hint:empty{display:none}"
	"body.pro .primary,body.pro select{border-radius:6px}"
	"body.pro .seg{border-radius:6px;background:var(--glass)}body.pro .seg button{border-radius:5px}"
	"body.pro .primary.toggle{background:var(--glass)}"
	"body.pro .primary.toggle.on{background:var(--accent)}"
	".sr{position:absolute;width:1px;height:1px;overflow:hidden;"
	"clip:rect(0 0 0 0);white-space:nowrap}"
	"@media(prefers-contrast:more){:root{--txt2:rgba(255,255,255,.9);"
	"--hair:rgba(255,255,255,.5);--glass:rgba(14,15,19,.95)}}"
	"@media(prefers-reduced-transparency:reduce){:root{"
	"--glass:rgba(14,15,19,.95)}.panel{backdrop-filter:none}}"
	"@media(prefers-reduced-motion:reduce){.dot{transition:none}}"
	"</style></head><body>"
	"<header><h1>LensLink</h1>"
	"<div class='pill'><span class='dot' id='dot'></span>"
	"<span id='status' data-t='Connecting'></span></div>"
	"<span class='sr' id='statusann' role='status' aria-live='polite'></span>"
	/* Pro section switch: shown with the live controls, remembered per
	 * browser. */
	"<button class='pill' id='probtn' style='display:none' data-t='Pro' "
	"data-t-title='Pro.Tip'></button>"
	"<button class='info' id='proinfo' style='display:none' data-t-title='Shortcuts' "
	"aria-expanded='false'>i</button>"
	/* Lip-sync calibration stage — hidden unless auto-calibrate is on
	 * AND a phone is connected: the plugin keeps its lock across
	 * reconnects (by design), but claiming "locked" beside a "trying to
	 * reach the phone" status reads as stale nonsense. The Recalibrate
	 * button appears only while locked — the one state where it acts. */
	"<div class='pill' id='syncpill' style='display:none'>"
	"<span class='dot' id='syncdot'></span>"
	"<span id='sync' aria-live='polite'></span>"
	"<button id='recal' style='display:none;border:0;cursor:pointer;"
	"background:var(--glass2,rgba(255,255,255,.12));color:inherit;"
	"border-radius:999px;font-size:12px;padding:2px 10px;margin-left:4px' "
	"data-t='Recalibrate'></button></div></header>"
	/* Source tabs: hidden until more than one camera source is live.
	 * Every API call carries the selected source's ?src= id. */
	"<div class='tip' id='protip' style='display:none' data-t='Shortcuts'></div>"
	"<div class='seg' id='srctabs' "
	"style='display:none;margin-bottom:12px;flex-wrap:wrap'></div>"
	/* Shown instead of the controls for a screen-mirror source. */
	"<div class='panel' id='screennote' style='display:none' "
	"data-t='ScreenNote'></div>"
	/* Remote start: the app is open but idle; one tap starts the camera. */
	"<div class='panel' id='startpanel' style='display:none'>"
	"<div class='btnrow'>"
	"<button class='primary' id='startbtn' data-t='StartCamera'></button>"
	"<button class='primary toggle' id='asbtn1' "
	"data-t-title='AutoStart.Tip' data-t='AutoStart'></button></div>"
	"<div class='hint' id='starthint' style='margin-top:12px' data-t='StartHint'></div>"
	"<div class='hint' id='armhint' style='margin-top:12px;display:none' "
	"data-t='NotArmedHint'></div></div>"
	/* Hidden until the first poll confirms a live camera connection —
	 * a default-visible panel flashed dead sliders and a Stop button
	 * before any state was known. */
	"<div class='panel' id='panel' style='display:none'>"
	/* Pro: the latest still with the phone's readout boxes on it; the
	 * value chips move onto it (proUI). */
	"<div class='frame proonly' id='proframe'><img id='proimg' alt=''>"
	"<div class='ptop'><div class='bx'><span class='ur'><span class='dot' id='pdot'></span>"
	"<span id='pstat'></span></span></div>"
	"<div class='bx'><span id='prate'>–</span><small>Mb/s</small></div>"
	"<div class='bx'><span class='ur' data-t-title='Latency'><span id='plat'>–</span><small>ms</small></span></div>"
	"<button class='bx' id='pfmt' data-t-title='Resolution'><span id='pfmt1'></span>"
	"<small id='pfmt2'></small></button></div></div>"
	/* Flashlight: left of the lenses, hidden on a camera without one;
	 * its brightness row appears while it is on (flashlightLevel). */
	"<div class='lenses'><button class='chip' id='fl' data-t-title='Flashlight' style='display:none'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='currentColor'>"
	"<path d='M13 2 L4 14 h6 l-1 8 9-12 h-6 z'/></svg></button>"
	"<div class='lensbtns' id='lensbtns'></div>"
	"<select id='lenssel' data-t-title='Lens' style='display:none'></select>"
	/* Green screen: hidden until the app's STATE advertises support
	 * (supportsGreenScreen). */
	"<button class='chip' id='gs' data-t-title='GreenScreen' style='display:none'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2' stroke-linecap='round'><circle cx='12' cy='8' r='4'/>"
	"<path d='M4 21 v-1 a8 8 0 0 1 16 0 v1'/></svg></button></div>"
	"<div class='row' id='zoomrow'>"
	"<input id='zoom' class='y' type='range' min='1' max='10' step='0.1' value='1' "
	"data-t-title='Zoom'>"
	"<span class='ro y' id='zv'>1&times;</span></div>"
	/* The subject-distance slider appears only while depth assist is
	 * actually running (greenScreenDepth). Same stops as the app's Subject dial
	 * (UI_DESIGN §5): 0.5-5.0 m, then "All" (sends 0) past the far end;
	 * clicking the readout hands the cutoff back to Auto (sends -1). */
	"<div class='row' id='rfrow' style='display:none'>"
	"<span class='lbl' id='rfl' data-t='Reframe'></span>"
	"<input id='rfz' class='y' type='range' min='1' max='4' step='0.1' value='1' "
	"aria-labelledby='rfl'>"
	"<span class='ro y' id='rfv' role='button' tabindex='0' "
	"data-t-title='Reframe.Tip'></span></div>"
	"<div class='pad' id='rfpad' tabindex='0' role='application' "
	"data-t-title='Reframe.Pad' style='display:none'><img id='rfimg' alt=''>"
	"<div id='rfwin'></div></div>"
	"<div class='row' id='rfhqrow' style='display:none'>"
	"<button class='primary toggle' id='rfhq' data-t='Reframe.HQ' "
	"data-t-title='Reframe.HQ.Tip'></button></div>"
	"<div class='row' id='flrow' style='display:none'>"
	"<span class='lbl' id='fll' data-t='Flashlight'></span>"
	"<input id='fld' class='y' type='range' min='1' max='100' step='1' value='100' "
	"aria-labelledby='fll'>"
	"<span class='ro y' id='flv' role='button' tabindex='0' "
	"data-t-title='FlashlightFull.Tip'></span></div>"
	"<div class='row' id='gsdrow' style='display:none'>"
	"<span class='lbl' id='gsdl' data-t='Subject'></span>"
	"<input id='gsd' class='y' type='range' min='0.5' max='5.5' step='0.1' value='5.5' "
	"aria-labelledby='gsdl'>"
	"<span class='ro y' id='gsdv' role='button' "
	"tabindex='0' data-t-title='SubjectAuto.Tip' data-t='Auto'></span></div>"
	"<div class='sep' id='tsep'></div>"
	"<div class='tchips' id='tchips'></div>"
	"<div class='dial'><div class='readout' id='readout' aria-hidden='true'></div>"
	"<input id='dial' class='y' type='range'>"
	"<div class='lights' id='lights' aria-hidden='true'>"
	"<svg style='left:calc(7px + (100% - 14px)*.0545)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><path d='M9 18h6M10 21h4M12 3a6 6 0 0 0-3 11v2h6v-2a6 6 0 0 0-3-11z'/></svg>"
	"<svg style='left:calc(7px + (100% - 14px)*.2727)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><rect x='3' y='6' width='18' height='8' rx='1'/><path d='M7 18h10'/></svg>"
	"<svg style='left:calc(7px + (100% - 14px)*.5455)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><circle cx='12' cy='12' r='4'/><path d='M12 2v3M12 19v3M2 12h3M19 12h3'/></svg>"
	"<svg style='left:calc(7px + (100% - 14px)*.7273)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><path d='M7 18a5 5 0 1 1 1-9.9A6 6 0 0 1 19 11a4 4 0 0 1-1 7z'/></svg>"
	"<svg style='left:calc(7px + (100% - 14px)*.9091)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><path d='M4 21V5l8-3v19M12 9h8v12'/></svg>"
	"</div></div>"
	"<div class='pmeters proonly'><span class='ur' data-t-title='Battery'>"
	"<span class='bat' aria-hidden='true'><div id='batfill'></div></span>"
	"<span id='batv'></span></span>"
	"<span class='lbl' style='min-width:0' data-t='Mic'></span>"
	"<div class='meter' aria-hidden='true'><div id='meterfill'></div></div>"
	"<span id='meterv'></span></div>"
	"<div class='still' id='stillbox' style='display:none'>"
	"<img id='still' alt='' role='button' tabindex='0'></div>"
	"<div class='tools'><span class='hint' id='toolhint' aria-live='polite'></span>"
	"<button class='chip' id='wbc' data-t-title='Calibrate.Tip' data-t-label='Calibrate'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M14 4l6 6-9 9H5v-6z'/><path d='M12 6l6 6'/></svg></button>"
	"<button class='chip' id='nb' data-t-title='NaturalBlur.Tip' data-t-label='NaturalBlur'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2'><circle cx='12' cy='12' r='9'/><path d='M12 3l3 7M21 12l-7 3M12 21l-3-7M3 12l7-3'/></svg></button>"
	"<span class='gap' id='toolgap'></span>"
	"<button class='chip' id='lock' data-t-title='Lock.Tip' data-t-label='Lock'>"
	"<svg class='ic lk-open' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2' stroke-linecap='round'><rect x='5' y='11' width='14' height='10' rx='2'/><path d='M8 11V7a4 4 0 0 1 7.5-2'/></svg>"
	"<svg class='ic lk-shut' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2' stroke-linecap='round'><rect x='5' y='11' width='14' height='10' rx='2'/><path d='M8 11V7a4 4 0 0 1 8 0v4'/></svg></button>"
	"<button class='chip' id='flashlight' data-t-title='Flashlight'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='currentColor'>"
	"<path d='M13 2 L4 14 h6 l-1 8 9-12 h-6 z'/></svg></button>"
	"<button class='chip' id='gd' data-t-title='Guides' style='display:none'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2'><rect x='3' y='5' width='18' height='14' rx='1'/>"
	"<path d='M9 5v14M15 5v14M3 10h18M3 14h18'/></svg></button>"
	"<button class='chip' id='flip' data-t-title='Flip'>"
	"<svg class='ic' aria-hidden='true' focusable='false' viewBox='0 0 24 24' fill='none' stroke='currentColor' "
	"stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>"
	"<path d='M15 4 h5 v5'/><path d='M20 9 A8 8 0 0 0 6 6'/>"
	"<path d='M9 20 H4 v-5'/><path d='M4 15 A8 8 0 0 0 18 18'/></svg></button></div>"
	"<div class='sep'></div>"
	/* Mic picker: shown while the app streams its mic as the source's
	 * audio (STATE micEnabled) — mirrors the app's mic row. */
	"<div class='row' id='microw' style='display:none'>"
	"<span class='lbl' data-t='Mic'></span>"
	"<select id='micsel' data-t-title='PhoneMic'></select></div>"
	/* Format row (resolution / fps / codec): shown once the app's STATE
	 * advertises its capability lists; older apps just never show it. */
	"<div class='row' id='fmtrow' style='display:none'>"
	"<select id='fmtres' data-t-title='Resolution'></select>"
	"<select id='fmtfps' data-t-title='FrameRate'></select>"
	"<select id='fmtcodec' data-t-title='Codec'></select>"
	"<select id='fmtcolor' data-t-title='Color' style='display:none'></select>"
	"<select id='fmtq' data-t-title='Bitrate' style='display:none'></select>"
	"</div>"
	/* Background blur test (TestFlight builds only): the modes the
	 * phone's lens and format can run (blurModes); hidden otherwise. */
	"<div class='row' id='blrow' style='display:none'>"
	"<span class='lbl' id='bll' data-t='Blur'></span>"
	"<div class='seg' id='blseg' role='group' aria-labelledby='bll'></div></div>"
	"<div class='row' id='stabrow' style='display:none'>"
	"<span class='lbl' id='stabl' data-t='Stabilization'></span>"
	"<select id='stab' aria-labelledby='stabl'></select></div>"
	"<div class='row' id='afrow' style='display:none'>"
	"<span class='lbl' id='afl' data-t='AntiFlicker'></span>"
	"<select id='af' aria-labelledby='afl'></select></div>"
	/* Remote stop: mirrors the app's red Stop. The phone drops back to
	 * standby, so this panel swaps to the Start button afterwards. */
	/* Pro: focus pull from A to B. */
	"<div class='proonly'>"
	"<div class='btnrow' id='pullrow' style='display:none'>"
	"<button class='primary toggle' id='fa' data-t='FocusA'></button>"
	"<button class='primary toggle' id='fb' data-t='FocusB'></button>"
	"<button class='primary' id='fpull' data-t='FocusPull' disabled></button>"
	"<select id='fsec' data-t-title='FocusPull' style='flex:none;width:80px'>"
	"<option value='1'>1 s</option><option value='2' selected>2 s</option>"
	"<option value='3'>3 s</option><option value='5'>5 s</option></select></div></div>"
	"<div class='btnrow'>"
	/* Hold the stream without ending it: the phone keeps the connection
	 * and the camera, OBS keeps the source, and resuming is a keyframe
	 * rather than a reconnect. Label follows the phone's state. */
	"<button class='primary toggle' id='pausebtn' data-t='Pause'></button>"
	"<button class='primary danger' id='stopbtn' data-t='StopCamera'></button>"
	"<button class='primary toggle' id='asbtn2' "
	"data-t-title='AutoStart.Tip' data-t='AutoStart'></button></div>"
	"</div>"
	"<script>"
	/* NB: elements are looked up explicitly — a bare `status` would
	 * resolve to window.status, not the element. */
	"const $=id=>document.getElementById(id);"
	"const t=k=>T[k]||k;"
	"document.querySelectorAll('[data-t]').forEach(e=>e.textContent=t(e.dataset.t));"
	"document.querySelectorAll('[data-t-title]').forEach(e=>{"
	"e.title=t(e.dataset.tTitle);"
	"if(!e.dataset.t)e.setAttribute('aria-label',"
	"e.dataset.tLabel?t(e.dataset.tLabel):e.title)});"
	"const pressed=(el,on)=>el.setAttribute('aria-pressed',on?'true':'false');"
	"const vt=(el,v)=>el.setAttribute('aria-valuetext',v);"
	"const setText=(el,v)=>{if(el.textContent!==v)el.textContent=v};"
	"const show=(el,on)=>{el.style.display=on?'':'none'};"
	"let annKey=null;"
	"const say=(k,v)=>{if(k!==annKey){annKey=k;$('statusann').textContent=v}};"
	"const syncEl=$('sync'),syncdotEl=$('syncdot'),syncpillEl=$('syncpill'),"
	"recalEl=$('recal'),"
	"dotEl=$('dot'),statusEl=$('status'),zoomEl=$('zoom'),zvEl=$('zv'),"
	"zoomrowEl=$('zoomrow'),lensbtnsEl=$('lensbtns'),lensselEl=$('lenssel'),"
	"flashlightEl=$('flashlight'),flipEl=$('flip'),"
	"panelEl=$('panel'),screennoteEl=$('screennote'),"
	"startpanelEl=$('startpanel'),startbtnEl=$('startbtn'),"
	"starthintEl=$('starthint'),armhintEl=$('armhint'),"
	"fmtrowEl=$('fmtrow'),fmtresEl=$('fmtres'),fmtfpsEl=$('fmtfps'),"
	"fmtcodecEl=$('fmtcodec'),stopbtnEl=$('stopbtn'),"
	"pausebtnEl=$('pausebtn'),"
	"asbtn1El=$('asbtn1'),asbtn2El=$('asbtn2'),"
	"tchipsEl=$('tchips'),dialEl=$('dial'),readoutEl=$('readout'),"
	"lightsEl=$('lights'),wbcEl=$('wbc'),nbEl=$('nb'),toolgapEl=$('toolgap'),"
	"lockEl=$('lock'),toolhintEl=$('toolhint'),stillboxEl=$('stillbox'),"
	"stillEl=$('still'),"
	"gsEl=$('gs'),gsdrowEl=$('gsdrow'),gsdEl=$('gsd'),gsdvEl=$('gsdv'),"
	"flEl=$('fl'),flrowEl=$('flrow'),fldEl=$('fld'),flvEl=$('flv'),"
	"stabrowEl=$('stabrow'),stabEl=$('stab'),"
	"blrowEl=$('blrow'),blsegEl=$('blseg'),"
	"microwEl=$('microw'),micselEl=$('micsel'),srctabsEl=$('srctabs');"
	"const COL={live:'#30D158',amber:'#FF9F0A',red:'#FF453A',grey:'#8E8E93',"
	"accent:'#3D7BFF'};"
	"const TONE={idle:COL.grey,wait:COL.amber,ready:COL.amber,live:COL.live,"
	"error:COL.red};"
	"const LENS={'Front':t('Lens.Front'),"
	"'Front (Ultra Wide)':t('Lens.FrontUltraWide'),'Main (Wide)':t('Lens.MainWide'),"
	"'Ultra Wide (0.5×)':t('Lens.UltraWide'),'Telephoto':t('Lens.Telephoto')};"
	/* Selected source id (from /api/sources); every request carries it.
	 * A 404 means that source is gone: drop the id and the next poll
	 * re-picks from the list. */
	"let src=null;const q=()=>src==null?'':('?src='+src);"
	"const gone=r=>{if(r.status===404)src=null;return r.status===404};"
	"let lastTouch=0;const touch=()=>lastTouch=Date.now();"
	"const send=o=>{touch();"
	"fetch('/api/control'+q(),{method:'POST',body:JSON.stringify(o)}).then(gone)};"
	"const deb=(f,ms)=>{let t;return(...a)=>{clearTimeout(t);"
	"t=setTimeout(()=>f(...a),ms)}};"
	"let S={};"
	"const newApp=()=>Array.isArray(S.lensFactors);"
	"const cmp=v=>String(+(+v).toPrecision(2));"
	"const front=l=>/^Front/.test(l||'');"
	"function lensUI(){const L=Array.isArray(S.lenses)?S.lenses:[];"
	"const F=S.lensFactors,z=+S.zoom||1;"
	"const has=Array.isArray(F)&&F.length===L.length&&L.length>0;"
	"show(lensselEl,!has&&L.length>1);"
	"if(!has){fillSel(lensselEl,L,S.lens||null,l=>LENS[l]||l);"
	"lensbtnsEl.replaceChildren();zvEl.textContent=z.toFixed(1)+'×';"
	"vt(zoomEl,zvEl.textContent);return}"
	"const side=front(S.lens);"
	"const crop=!side&&S.maxZoom>1&&+S.cropZoom>1?+S.cropZoom:0;"
	"const items=L.map((l,i)=>({l,f:+F[i]||1})).filter(x=>front(x.l)===side)"
	".sort((a,b)=>a.f-b.f);"
	"const btns=[];"
	"items.forEach(x=>{const sel=x.l===S.lens;"
	"const onCrop=sel&&crop&&x.l==='Main (Wide)'&&Math.abs(z-crop)<0.01;"
	"const act=sel&&!onCrop;"
	"btns.push([act?cmp(x.f*z)+'×':cmp(x.f).replace(/^0\\./,'.'),act,x.l,0]);"
	"if(crop&&x.l==='Main (Wide)')"
	"btns.push([onCrop?cmp(crop)+'×':cmp(crop),onCrop,x.l,crop])});"
	"const k=JSON.stringify(btns);"
	"if(lensbtnsEl.dataset.k!==k){lensbtnsEl.dataset.k=k;"
	"const fi=[...lensbtnsEl.children].indexOf(document.activeElement);"
	/* textContent, not innerHTML: lens labels come from the device. */
	"lensbtnsEl.replaceChildren(...btns.map(([label,on,l,c])=>{"
	"const b=document.createElement('button');b.className=on?'lb on':'lb';"
	"b.textContent=label;b.dataset.l=l;if(c)b.dataset.crop=c;"
	"b.setAttribute('aria-label',(LENS[l]||l)+(c?' '+cmp(c)+'×':''));"
	"pressed(b,on);return b}));"
	"if(fi>=0&&lensbtnsEl.children[fi])lensbtnsEl.children[fi].focus()}"
	"const cur=items.find(x=>x.l===S.lens);"
	"zvEl.textContent=cmp((cur?cur.f:1)*z)+'×';vt(zoomEl,zvEl.textContent)}"
	"lensbtnsEl.onclick=e=>{const b=e.target.closest('button');if(!b)return;"
	"touch();const l=b.dataset.l,sel=l===S.lens;"
	"if(!sel)send({cmd:'selectLens',label:l});"
	"const z=b.dataset.crop?+b.dataset.crop:1;"
	"if(sel||z!==1)send({cmd:'zoom',value:z});"
	"S.lens=l;S.zoom=z;zoomEl.value=z;lensUI()};"
	"lensselEl.onchange=()=>send({cmd:'selectLens',label:lensselEl.value});"
	"const dz=deb(()=>send({cmd:'zoom',value:+zoomEl.value}),60);"
	"zoomEl.oninput=()=>{touch();S.zoom=+zoomEl.value;lensUI();dz()};"
	"const EVS=[];for(let i=-6;i<=6;i++)EVS.push(i/3);"
	"const ISOS=[25,32,40,50,64,80,100,125,160,200,250,320,400,500,640,800,"
	"1000,1250,1600,2000,2500,3200,4000,5000,6400,8000,10000,12800,16000,"
	"20000,25600];"
	"const SHD=[1,2,3,4,5,6,8,10,13,15,20,24,25,30,40,48,50,60,80,100,120,125,"
	"160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000,5000,"
	"6400,8000];"
	"function isoStops(){const lo=S.minISO||34,hi=S.maxISO||3072;"
	"const s=ISOS.filter(v=>v>=lo&&v<=hi);return s.length>1?s:[lo,hi]}"
	"function shStops(){"
	"const lo=Math.max(S.minShutterSeconds||1/8000,1/8000)*0.999;"
	"const hi=(S.maxShutterSeconds||1/30)*1.001;"
	"const s=SHD.map(d=>1/d).filter(v=>v>=lo&&v<=hi);return s.length>1?s:[hi,lo]}"
	"const nearest=(a,v)=>a.reduce((b,x,i)=>Math.abs(x-v)<Math.abs(a[b]-v)?i:b,0);"
	"const SHD=[2,3,4,5,6,8,10,13,15,20,24,25,30,40,48,50,60,80,96,100,120,125,160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000,5000,6400,8000];"
	"const shLabel=s=>{if(s>=1)return Math.round(s)+'s';const x=1/s,u=SHD.reduce((a,b)=>Math.abs(b-x)<Math.abs(a-x)?b:a);return '1/'+Math.round(Math.abs(u-x)<=u*0.03?u:x);};"
	"const NAME={focus:()=>t('Focus'),wb:()=>t('WB'),ev:()=>'EV',iso:()=>'ISO',"
	"sh:()=>t('Shutter'),tint:()=>t('Tint')};"
	/* ISO and shutter lock one at a time on an app that reports
	 * isoMode/shutterMode; older apps hold them as one exposure pair. */
	"const split=()=>typeof S.isoMode==='string';"
	"const GRP={focus:'focus',wb:'whiteBalance',tint:'whiteBalance',ev:'exposure',"
	"iso:'exposure',sh:'exposure'};"
	"const grp=k=>split()&&k==='iso'?'iso':split()&&k==='sh'?'shutter':GRP[k];"
	"const isoMan=()=>split()?S.isoMode==='manual':S.exposureMode==='manual';"
	"const shMan=()=>split()?S.shutterMode==='manual':S.exposureMode==='manual';"
	"const eman=()=>isoMan()&&shMan();"
	"const locked=g=>g==='focus'?S.focusMode==='locked'"
	":g==='whiteBalance'?S.whiteBalanceMode==='locked'"
	":g==='iso'?isoMan():g==='shutter'?shMan():eman();"
	"const isAuto=k=>k==='ev'?null:!locked(grp(k));"
	"let tgt='ev';"
	"function targets(){const a=['focus'];if(S.supportsWhiteBalanceLock)a.push('wb');"
	/* Tint takes a value only on apps that also report "monitor". */
	"if(S.supportsWhiteBalanceLock&&S.monitor)a.push('tint');"
	"a.push('ev');if(S.supportsManualExposure)a.push('iso','sh');return a}"
	"function readout(k){switch(k){"
	"case 'ev':{const b=+S.exposureBias||0;return(b>=0?'+':'')+b.toFixed(1)+' EV'}"
	"case 'iso':return isoMan()?'ISO '+Math.round(S.iso):t('Auto');"
	"case 'sh':return shMan()?shLabel(S.shutterSeconds):t('Auto');"
	"case 'wb':return isAuto('wb')?t('Auto'):Math.round(S.whiteBalanceTemperature)+' K';"
	"case 'tint':{if(isAuto('tint'))return t('Auto');const n=Math.round(+S.whiteBalanceTint||0);"
	"return(n>=0?'+':'')+n}"
	"default:return isAuto('focus')?t('Auto'):(+S.lensPosition||0).toFixed(2)}}"
	/* The value a Pro box shows: the number alone, in the phone's form. */
	"const sgn=n=>(n>=0?'+':'')+n;"
	"function pv(k){switch(k){"
	"case 'ev':return sgn((+S.exposureBias||0).toFixed(1));"
	"case 'iso':return S.iso?String(Math.round(S.iso)):'–';"
	"case 'sh':return S.shutterSeconds?shLabel(S.shutterSeconds):'–';"
	"case 'wb':return S.whiteBalanceTemperature?Math.round(S.whiteBalanceTemperature)+'K':'–';"
	"case 'tint':return sgn(Math.round(+S.whiteBalanceTint||0));"
	"default:return isAuto('focus')?t('Auto'):(+S.lensPosition||0).toFixed(2)}}"
	"function trayUI(){const ts=targets();if(!ts.includes(tgt))tgt='ev';"
	"const k=ts.map(x=>x+(x===tgt?'*':'')+isAuto(x)).join();"
	"if(tchipsEl.dataset.k!==k){tchipsEl.dataset.k=k;"
	"const fk=tchipsEl.contains(document.activeElement)?document.activeElement.dataset.k:null;"
	"tchipsEl.replaceChildren(...ts.map(x=>{const b=document.createElement('button');"
	"const a=isAuto(x);b.className=x===tgt?'tc on':'tc';b.dataset.k=x;"
	"b.textContent=NAME[x]();pressed(b,x===tgt);"
	"const vs=document.createElement('span');vs.className='v';"
	"vs.setAttribute('aria-hidden','true');b.appendChild(vs);"
	"b.setAttribute('aria-label',NAME[x]()+(a?', '+t('Auto'):''));"
	"if(a){const s=document.createElement('span');s.className='a';"
	"s.textContent='A';s.setAttribute('aria-hidden','true');b.appendChild(s)}"
	"return b}));"
	"if(fk)tchipsEl.querySelector('[data-k='+fk+']').focus()}"
	"for(const b of tchipsEl.children)setText(b.querySelector('.v'),pv(b.dataset.k));"
	"let stops=null,v=0;"
	"if(tgt==='ev'){stops=EVS;v=+S.exposureBias||0}"
	"else if(tgt==='iso'){stops=isoStops();v=+S.iso||100}"
	"else if(tgt==='sh'){stops=shStops();v=+S.shutterSeconds||1/60}"
	"if(stops){dialEl.min=0;dialEl.max=stops.length-1;dialEl.step=1;"
	"dialEl.value=nearest(stops,v)}"
	"else if(tgt==='wb'){dialEl.min=2500;dialEl.max=8000;dialEl.step=10;"
	"dialEl.value=+S.whiteBalanceTemperature||5000}"
	"else if(tgt==='tint'){dialEl.min=-150;dialEl.max=150;dialEl.step=1;"
	"dialEl.value=+S.whiteBalanceTint||0}"
	"else{dialEl.min=0;dialEl.max=1;dialEl.step=0.01;dialEl.value=+S.lensPosition||0.5}"
	"dialEl.disabled=tgt==='ev'&&eman();"
	"setText(readoutEl,readout(tgt));dialEl.setAttribute('aria-label',NAME[tgt]());"
	"vt(dialEl,readoutEl.textContent);"
	"show(lightsEl,tgt==='wb');show(wbcEl,tgt==='wb');"
	"show(nbEl,tgt==='sh'&&typeof S.naturalBlur==='boolean');"
	"show(toolgapEl,tgt!=='wb'&&nbEl.style.display==='none');"
	"nbEl.className=S.naturalBlur?'chip on':'chip';pressed(nbEl,!!S.naturalBlur);"
	/* It caps an automatic shutter: idle while the shutter is by hand. */
	"nbEl.disabled=shMan();"
	"const lk=locked(grp(tgt));lockEl.className=lk?'chip on':'chip';pressed(lockEl,lk);"
	"flashlightEl.className=S.flashlight?'chip on':'chip';"
	"pressed(flashlightEl,!!S.flashlight);"
	"flashlightEl.disabled=S.hasFlashlight===false}"
	"tchipsEl.onclick=e=>{const b=e.target.closest('button');if(!b)return;"
	"touch();const k=b.dataset.k;"
	"if(k!==tgt){tgt=k;stillClose()}"
	"else if(k==='ev'){if(!eman()){S.exposureBias=0;send({cmd:'exposure_bias',value:0})}}"
	"else if(isAuto(k)===false){setLocal(grp(k),false);legacyLock(grp(k),false)}"
	"trayUI()};"
	"const sendDial=deb(()=>{switch(tgt){"
	"case 'ev':send({cmd:'exposure_bias',value:S.exposureBias});break;"
	"case 'iso':send(split()?{cmd:'exposure',isoMode:'manual',iso:S.iso}"
	":{cmd:'exposure',mode:'manual',iso:S.iso});break;"
	"case 'sh':send(split()?{cmd:'exposure',shutterMode:'manual',"
	"shutterSeconds:S.shutterSeconds}"
	":{cmd:'exposure',mode:'manual',shutterSeconds:S.shutterSeconds});break;"
	"case 'wb':case 'tint':send({cmd:'white_balance',mode:'locked',"
	"temperature:S.whiteBalanceTemperature,tint:+S.whiteBalanceTint||0});break;"
	"default:send({cmd:'focus',mode:'locked',lensPosition:S.lensPosition})}},60);"
	"dialEl.oninput=()=>{touch();const v=+dialEl.value;"
	"if(tgt!=='ev'&&isAuto(tgt)&&newApp())"
	"send({cmd:'lock',target:grp(tgt),on:true});"
	"if(tgt==='ev')S.exposureBias=EVS[v];"
	"else if(tgt==='iso')S.iso=isoStops()[v];"
	"else if(tgt==='sh')S.shutterSeconds=shStops()[v];"
	"else if(tgt==='wb')S.whiteBalanceTemperature=v;"
	"else if(tgt==='tint')S.whiteBalanceTint=v;"
	"else S.lensPosition=v;"
	"if(tgt!=='ev')setLocal(grp(tgt),true);"
	"trayUI();sendDial()};"
	"function setLocal(g,on){if(g==='focus')S.focusMode=on?'locked':'auto';"
	"else if(g==='whiteBalance')S.whiteBalanceMode=on?'locked':'auto';"
	"else if(g==='iso')S.isoMode=on?'manual':'auto';"
	"else if(g==='shutter')S.shutterMode=on?'manual':'auto';"
	"else{S.exposureMode=on?'manual':'auto';"
	"if(split())S.isoMode=S.shutterMode=S.exposureMode}"
	"if(split())S.exposureMode=S.isoMode==='manual'||S.shutterMode==='manual'"
	"?'manual':'auto'}"
	"function legacyLock(g,on){if(g==='focus')send(on?{cmd:'focus',mode:'locked',"
	"lensPosition:+S.lensPosition}:{cmd:'focus',mode:'auto'});"
	"else if(g==='whiteBalance')send(on?{cmd:'white_balance',mode:'locked',"
	"temperature:+S.whiteBalanceTemperature}:{cmd:'white_balance',mode:'auto'});"
	"else if(g==='iso')send({cmd:'exposure',isoMode:on?'manual':'auto',iso:+S.iso});"
	"else if(g==='shutter')send({cmd:'exposure',shutterMode:on?'manual':'auto',"
	"shutterSeconds:+S.shutterSeconds});"
	"else send(on?{cmd:'exposure',mode:'manual',iso:+S.iso,"
	"shutterSeconds:+S.shutterSeconds}:{cmd:'exposure',mode:'auto'})}"
	"lockEl.onclick=e=>{touch();"
	"const gs=e.shiftKey?['focus'].concat(S.supportsWhiteBalanceLock?['whiteBalance']:[],"
	"S.supportsManualExposure?['exposure']:[]):[grp(tgt)];"
	"const on=!gs.every(locked);gs.forEach(g=>setLocal(g,on));"
	"if(newApp())send({cmd:'lock',target:e.shiftKey?'all':gs[0],on});"
	"else gs.forEach(g=>legacyLock(g,on));"
	"trayUI()};"
	"nbEl.onclick=()=>{touch();S.naturalBlur=!S.naturalBlur;"
	"send({cmd:'natural_blur',on:S.naturalBlur});trayUI()};"
	"flashlightEl.onclick=()=>{touch();S.flashlight=!S.flashlight;"
	"send({cmd:'flashlight',on:S.flashlight});trayUI();flUI()};"
	"flipEl.onclick=()=>send({cmd:'flip'});"
	/* Lens-row Flashlight: a click switches it (the web has no hold);
	 * the row's slider sets brightness, its readout puts it back to
	 * full, like a second tap on the app's button. */
	"const flLabel=v=>Math.round(v*100)+'%';"
	"function flUI(){const on=!!S.flashlight,lv=+S.flashlightLevel||1;"
	"show(flEl,S.hasFlashlight===true);flEl.className=on?'chip on':'chip';"
	"pressed(flEl,on);"
	"show(flrowEl,on&&S.hasFlashlight===true&&typeof S.flashlightLevel==='number');"
	"fldEl.value=Math.round(lv*100);flvEl.textContent=flLabel(lv);"
	"vt(fldEl,flvEl.textContent)}"
	"flEl.onclick=()=>{touch();S.flashlight=!S.flashlight;"
	"send({cmd:'flashlight',on:S.flashlight});flUI();trayUI()};"
	"const dFl=deb(()=>send({cmd:'flashlight',level:S.flashlightLevel}),60);"
	"fldEl.oninput=()=>{touch();S.flashlightLevel=+fldEl.value/100;flUI();dFl()};"
	"flvEl.onclick=()=>{touch();S.flashlightLevel=1;flUI();"
	"send({cmd:'flashlight',level:1})};"
	"flvEl.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){"
	"e.preventDefault();flvEl.onclick()}};"
	"let picking=0;"
	"function stillClose(){picking=0;show(stillboxEl,false);"
	"wbcEl.classList.remove('on');pressed(wbcEl,false);setText(toolhintEl,'')}"
	"wbcEl.onclick=async()=>{touch();if(picking){stillClose();return}"
	"const me=picking=Date.now();wbcEl.classList.add('on');pressed(wbcEl,true);"
	"setText(toolhintEl,t('Calibrate.Pick'));"
	"try{if(gone(await fetch('/api/still'+q(),{method:'POST'})))return;"
	"for(let i=0;i<20&&picking===me;i++){"
	"await new Promise(r=>setTimeout(r,150));touch();"
	"const r=await fetch('/api/still'+q());if(gone(r))return;"
	"if(r.status===200){const b=await r.blob();if(picking!==me)return;"
	"if(stillEl.src)URL.revokeObjectURL(stillEl.src);"
	"stillEl.src=URL.createObjectURL(b);show(stillboxEl,true);return}}}catch(e){}"
	"if(picking===me){stillClose();setText(toolhintEl,t('Calibrate.NoPicture'))}};"
	"const boost=im=>{const c=document.createElement('canvas');c.width=c.height=16;"
	"const g=c.getContext('2d');g.drawImage(im,0,0,16,16);let m=0;"
	"const d=g.getImageData(0,0,16,16).data;"
	"for(let i=0;i<d.length;i+=4)m+=d[i]+d[i+1]+d[i+2];m/=256*3*255;"
	"im.style.filter='brightness('+Math.min(Math.max(0.45/(m||1),1),4)+')'};"
	"stillEl.onload=()=>boost(stillEl);"
	"const pick=(x,y)=>{send({cmd:'white_balance',mode:'calibrate',x,y});stillClose()};"
	"stillEl.onclick=e=>{const r=stillEl.getBoundingClientRect();"
	"pick(Math.min(Math.max((e.clientX-r.left)/r.width,0),1),"
	"Math.min(Math.max((e.clientY-r.top)/r.height,0),1))};"
	"stillEl.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();"
	"pick(0.5,0.5)}};"
	"document.addEventListener('keydown',e=>{if(e.key==='Escape'&&picking)stillClose()});"
	"startbtnEl.onclick=()=>send({cmd:'start_stream'});"
	"stopbtnEl.onclick=()=>send({cmd:'stop_stream'});"
	"let paused=false;"
	"function pauseUI(on){paused=on;"
	"pausebtnEl.textContent=on?t('Resume'):t('Pause');"
	"pausebtnEl.className=on?'primary toggle on':'primary toggle'}"
	"pausebtnEl.onclick=()=>{touch();pauseUI(!paused);"
	"send({cmd:paused?'pause_stream':'resume_stream'})};"
	/* Auto-start toggle: writes the source's own auto-start property
	 * (the checkbox in the source properties), not a phone control. */
	"let autoStart=false;"
	"function asUI(on){autoStart=on;const c=on?'primary toggle on':'primary toggle';"
	"asbtn1El.className=c;asbtn2El.className=c;"
	"pressed(asbtn1El,on);pressed(asbtn2El,on)}"
	"const toggleAS=()=>{touch();asUI(!autoStart);"
	"fetch('/api/autostart'+q(),{method:'POST',body:JSON.stringify({on:autoStart})}).then(gone)};"
	"asbtn1El.onclick=toggleAS;asbtn2El.onclick=toggleAS;"
	/* Rebuild a select only when its option list changes (same pattern as
	 * the lens picker); values stay raw, labels get a formatter. */
	"function fillSel(el,opts,val,fmt){const want=opts.join('|');"
	"if(el.dataset.opts!==want){el.dataset.opts=want;"
	"el.replaceChildren(...opts.map(o=>{const x=document.createElement('option');"
	"x.value=o;x.textContent=fmt?fmt(o):o;return x}))}"
	"if(val!=null)el.value=val}"
	"const CODEC_NAMES={h264:'H.264',hevc:'HEVC'};"
	"fmtresEl.onchange=()=>send({cmd:'set_format',resolution:fmtresEl.value});"
	"fmtfpsEl.onchange=()=>send({cmd:'set_format',fps:+fmtfpsEl.value});"
	"fmtcodecEl.onchange=()=>send({cmd:'set_format',codec:fmtcodecEl.value});"
	"const fmtcolorEl=$('fmtcolor');"
	"const COLORS={sdr:t('Color.SDR'),hlg:t('Color.HLG'),log:t('Color.Log')};"
	"fmtcolorEl.onchange=()=>send({cmd:'set_format',color:fmtcolorEl.value});"
	"const fmtqEl=$('fmtq');fmtqEl.onchange=()=>send({cmd:'set_quality',quality:fmtqEl.value});"
	"const STAB={off:t('Stabilization.Off'),standard:t('Stabilization.Standard'),"
	"cinematic:t('Stabilization.Cinematic')};"
	"stabEl.onchange=()=>send({cmd:'stabilization',mode:stabEl.value});"
	"const afEl=$('af');afEl.onchange=()=>send({cmd:'anti_flicker',mode:afEl.value});"
	"const rfrowEl=$('rfrow'),rfzEl=$('rfz'),rfvEl=$('rfv'),rfpadEl=$('rfpad'),"
	"rfwinEl=$('rfwin'),rfhqrowEl=$('rfhqrow'),rfhqEl=$('rfhq'),rfimgEl=$('rfimg');"
	"let rfBg=false,rfBusy=false,rfTry=0,rfZoomed=false;"
	"async function rfStill(){if(rfBusy)return;rfBusy=true;rfTry=Date.now();try{"
	"if(gone(await fetch('/api/still'+q(),{method:'POST'})))return;"
	"for(let i=0;i<20;i++){await new Promise(r=>setTimeout(r,150));"
	"const r=await fetch('/api/still'+q());if(gone(r))return;"
	"if(r.status===200){const b=await r.blob();"
	"if(rfimgEl.src)URL.revokeObjectURL(rfimgEl.src);"
	"rfimgEl.onload=()=>boost(rfimgEl);rfimgEl.src=URL.createObjectURL(b);"
	"rfBg=true;rfpadEl.classList.add('bg');return}}}catch(e){}finally{rfBusy=false}}"
	"let rfhq=false;"
	"function hqUI(on){rfhq=on;rfhqEl.className=on?'primary toggle on':'primary toggle';"
	"pressed(rfhqEl,on)}"
	"rfhqEl.onclick=()=>{touch();hqUI(!rfhq);send({cmd:'reframe',hq:rfhq})};"
	"let RF={zoom:1,x:.5,y:.5};"
	"function rfUI(){RF.zoom=Math.min(Math.max(RF.zoom,1),4);const h=.5/RF.zoom;"
	"RF.x=Math.min(Math.max(RF.x,h),1-h);RF.y=Math.min(Math.max(RF.y,h),1-h);"
	"rfzEl.value=RF.zoom;rfvEl.textContent=RF.zoom.toFixed(1)+'×';vt(rfzEl,rfvEl.textContent);"
	"const zd=RF.zoom>1.01;if(zd!==rfZoomed){rfZoomed=zd;if(!zd)setTimeout(rfStill,700)}"
	"const s=rfwinEl.style;"
	"s.left=(RF.x-h)*100+'%';s.top=(RF.y-h)*100+'%';"
	"s.width=s.height=100/RF.zoom+'%'}"
	"const dRf=deb(()=>send({cmd:'reframe',zoom:RF.zoom,x:RF.x,y:RF.y}),60);"
	"rfzEl.oninput=()=>{touch();RF.zoom=+rfzEl.value;rfUI();dRf()};"
	"rfvEl.onclick=()=>{touch();RF={zoom:1,x:.5,y:.5};rfUI();"
	"send({cmd:'reframe',zoom:1})};"
	"rfvEl.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){"
	"e.preventDefault();rfvEl.onclick()}};"
	"const rfAt=e=>{const r=rfpadEl.getBoundingClientRect();touch();"
	"RF.x=(e.clientX-r.left)/r.width;RF.y=(e.clientY-r.top)/r.height;rfUI();dRf()};"
	"rfpadEl.onpointerdown=e=>{rfpadEl.setPointerCapture(e.pointerId);rfAt(e)};"
	"rfpadEl.onpointermove=e=>{if(rfpadEl.hasPointerCapture(e.pointerId))rfAt(e)};"
	"rfpadEl.onkeydown=e=>{const d={ArrowLeft:[-1,0],ArrowRight:[1,0],"
	"ArrowUp:[0,-1],ArrowDown:[0,1]}[e.key];if(!d)return;e.preventDefault();"
	"touch();RF.x+=d[0]*.05;RF.y+=d[1]*.05;rfUI();dRf()};"
	/* Green screen: optimistic chip toggle. The slider sets a cutoff
	 * (0.5-5.0 m, All past 5); Auto (-1) is the readout's click, like
	 * tapping the app's Subject button while its dial is open. */
	"let gson=false;"
	"let blKey='';"
	"function blUI(){const m=Array.isArray(S.blurModes)?S.blurModes:[];"
	"show(blrowEl,m.length>1);const k=m.join()+'|'+S.blur;if(k===blKey)return;"
	"blKey=k;blsegEl.textContent='';"
	"const N={off:t('Blur.Off'),depth:t('Blur.Depth'),cinematic:t('Blur.Cinematic')};"
	"for(const x of m){const b=document.createElement('button');"
	"b.textContent=N[x]||x;b.className=x===S.blur?'on':'';pressed(b,x===S.blur);"
	"b.onclick=()=>{touch();S.blur=x;blUI();send({cmd:'blur',mode:x})};"
	"blsegEl.appendChild(b)}}"
	"function gsUI(on){gson=on;gsEl.className=on?'chip on':'chip';pressed(gsEl,on)}"
	"gsEl.onclick=()=>{touch();gsUI(!gson);send({cmd:'green_screen',on:gson})};"
	"const gsLabel=v=>v<0?t('Auto'):v?v.toFixed(1)+' m':t('All');"
	"const gsVal=()=>+gsdEl.value>5.05?0:+gsdEl.value;"
	"const dGs=deb(()=>send({cmd:'green_screen',maxDistance:gsVal()}),60);"
	"gsdEl.oninput=()=>{touch();gsdvEl.textContent=gsLabel(gsVal());"
	"vt(gsdEl,gsdvEl.textContent);dGs()};"
	"gsdvEl.onclick=()=>{touch();gsdvEl.textContent=gsLabel(-1);"
	"vt(gsdEl,gsdvEl.textContent);"
	"send({cmd:'green_screen',maxDistance:-1})};"
	"gsdvEl.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){"
	"e.preventDefault();gsdvEl.onclick()}};"
	"micselEl.onchange=()=>send({cmd:'mic',id:micselEl.value});"
	/* Optimistic flip to 'relocking'; the 1 Hz poll corrects if lost. */
	"recalEl.onclick=()=>{recalEl.style.display='none';"
	"syncEl.textContent=t('Sync.Relocking');"
	"syncdotEl.style.background=COL.amber;"
	"fetch('/api/recalibrate'+q(),{method:'POST'}).then(gone)};"
	/* Pro: the phone's Pro overlay. The value chips move onto the still. */
	"const probtnEl=$('probtn'),proinfoEl=$('proinfo'),protipEl=$('protip'),gdEl=$('gd');"
	"let pro=false;try{pro=localStorage.getItem('lenslinkPro')==='1'}catch(e){}"
	"function proUI(){probtnEl.className=pro?'pill on':'pill';pressed(probtnEl,pro);"
	"document.body.classList.toggle('pro',pro);"
	"if(pro)$('proframe').appendChild(tchipsEl);else $('tsep').after(tchipsEl)}"
	"probtnEl.onclick=()=>{pro=!pro;try{localStorage.setItem('lenslinkPro',pro?'1':'0')}"
	"catch(e){}proUI();if(pro)proStill()};"
	"$('pfmt').onclick=()=>{fmtrowEl.scrollIntoView({block:'center'});fmtresEl.focus()};"
	"proinfoEl.onclick=()=>{const o=protipEl.style.display==='none';show(protipEl,o);"
	"proinfoEl.setAttribute('aria-expanded',o)};"
	"let prevB=null;"
	"function proLive(s){setText($('pstat'),s.status||'');"
	"$('pdot').style.background=TONE[s.tone]||COL.grey;"
	"if(prevB&&s.sampleMs>prevB.ms&&s.bytes>=prevB.b)setText($('prate'),"
	"((s.bytes-prevB.b)*8/(s.sampleMs-prevB.ms)/1000).toFixed(1));"
	"prevB={b:+s.bytes||0,ms:+s.sampleMs||0};"
	"setText($('plat'),s.latencyMs>0?String(s.latencyMs):'–');"
	"setText($('pfmt1'),[S.resolution,S.fps].filter(Boolean).join(' · '));"
	"setText($('pfmt2'),[CODEC_NAMES[S.codec]||S.codec,"
	"S.color==='log'?'LOG':S.hdr?'HLG':''].filter(Boolean).join(' '));"
	"const bt=typeof S.battery==='number'?S.battery:null,bf=$('batfill');"
	"setText($('batv'),bt==null?'–':bt+'%');bf.style.width=(bt||0)+'%';"
	"bf.style.background=bt!=null&&bt<=20?COL.red:'#fff';"
	"const fill=$('meterfill');"
	"if(s.audioPeak>=0){const db=s.audioPeak>0?20*Math.log10(s.audioPeak/32767):-90;"
	"fill.style.width=Math.min(Math.max((db+48)/48,0),1)*100+'%';"
	"fill.style.background=db>-3?COL.red:db>-12?'#FFD60A':COL.live;"
	"setText($('meterv'),db.toFixed(0)+' dBFS')}"
	"else{fill.style.width='0';setText($('meterv'),t('Guides.Off'))}}"
	"let hBusy=false,hLast=0;"
	"async function proStill(){if(hBusy||!pro||picking||rfBusy)return;hBusy=true;"
	"hLast=Date.now();try{"
	"if(gone(await fetch('/api/still'+q(),{method:'POST'})))return;"
	"for(let i=0;i<20;i++){await new Promise(r=>setTimeout(r,150));"
	"const r=await fetch('/api/still'+q());if(gone(r))return;"
	"if(r.status===200){const im=$('proimg');if(im.src)URL.revokeObjectURL(im.src);"
	"im.onload=()=>boost(im);im.src=URL.createObjectURL(await r.blob());return}}}"
	"catch(e){}finally{hBusy=false}}"
	"const GUIDES=['off','grid','2.39','1.85','4:3'];"
	"function monUI(){const m=S.monitor;show(gdEl,!!m);"
	"show($('pullrow'),!!m);if(!m)return;const g=m.guide||'off';"
	"gdEl.className=g==='off'?'chip':'chip on';pressed(gdEl,g!=='off');"
	"gdEl.title=t('Guides')+': '+(g==='off'?t('Guides.Off'):g==='grid'?t('Guides.Grid'):g)}"
	"gdEl.onclick=()=>{if(S.monitor)"
	"monSend({guide:GUIDES[(GUIDES.indexOf(S.monitor.guide)+1)%GUIDES.length]})};"
"const monSend=o=>{touch();if(!S.monitor)return;Object.assign(S.monitor,o);"
	"send(Object.assign({cmd:'monitor'},o));monUI()};"
		"let FA=null,FB=null,toB=true;"
	"function pullUI(){$('fa').className=FA!=null?'primary toggle on':'primary toggle';"
	"$('fb').className=FB!=null?'primary toggle on':'primary toggle';"
	"$('fpull').disabled=FA==null||FB==null}"
	"$('fa').onclick=()=>{FA=+S.lensPosition||0;toB=true;pullUI()};"
	"$('fb').onclick=()=>{FB=+S.lensPosition||0;pullUI()};"
	"$('fpull').onclick=()=>{touch();const v=toB?FB:FA;toB=!toB;"
	"S.lensPosition=v;S.focusMode='locked';"
	"send({cmd:'focus',mode:'locked',lensPosition:v,rampSeconds:+$('fsec').value});trayUI()};"
	/* Keyboard shortcuts: never while typing in a field, and Space
	 * stays a button press on a focused button. */
	"document.addEventListener('keydown',e=>{"
	"if(e.metaKey||e.ctrlKey||e.altKey||panelEl.style.display==='none')return;"
	"const tg=e.target.tagName||'',k=e.key;"
	"if(/^(INPUT|SELECT|TEXTAREA)$/.test(tg)||(k===' '&&tg==='BUTTON'))return;"
	"let done=true;"
	"if(k===' ')pausebtnEl.click();"
	"else if(/^[1-9]$/.test(k)){const b=lensbtnsEl.children[+k-1];if(b)b.click();else done=false}"
	"else if(k==='l'||k==='L')lockEl.dispatchEvent(new MouseEvent('click',{shiftKey:true}));"
	"else if((k==='a'||k==='A')&&newApp()){touch();send({cmd:'lock',target:'all',on:false})}"
	"else if((k==='g'||k==='G')&&S.monitor)"
	"monSend({guide:GUIDES[(GUIDES.indexOf(S.monitor.guide)+1)%GUIDES.length]});"
	"else if(k==='['||k===']'){touch();"
	"const v=Math.min(Math.max((+S.lensPosition||0)+(k===']'?.02:-.02),0),1);"
	"S.lensPosition=v;S.focusMode='locked';"
	"send({cmd:'focus',mode:'locked',lensPosition:v});trayUI()}"
	"else if(k==='-'||k==='='||k==='+'){if(eman())return;touch();"
	"const v=Math.round(((+S.exposureBias||0)+(k==='-'?-1/3:1/3))*3)/3;"
	"S.exposureBias=Math.min(Math.max(v,-2),2);"
	"send({cmd:'exposure_bias',value:S.exposureBias});trayUI()}"
	"else done=false;"
	"if(done)e.preventDefault()});"
	"async function poll(){try{"
	/* Source list first: pick/keep a selection, tabs when >1. */
	"const sj=await(await fetch('/api/sources')).json();"
	"const list=sj.sources||[];"
	"if(!list.length){setText(statusEl,t('NoSources'));say('none',t('NoSources'));"
	"dotEl.style.background=COL.grey;srctabsEl.style.display='none';"
	"panelEl.style.display='none';startpanelEl.style.display='none';"
	"screennoteEl.style.display='none';return}"
	"if(src==null||!list.some(x=>x.id===src))src=list[0].id;"
	"srctabsEl.style.display=list.length>1?'':'none';"
	"const sk=list.map(x=>x.id+':'+x.name).join('|')+'@'+src;"
	/* textContent, not innerHTML: source names are user data. */
	"if(srctabsEl.dataset.k!==sk){srctabsEl.dataset.k=sk;"
	"srctabsEl.replaceChildren(...list.map(x=>{"
	"const b=document.createElement('button');b.textContent=x.name;"
	"b.className=x.id===src?'on':'';pressed(b,x.id===src);"
	"b.onclick=()=>{src=x.id;lastTouch=0;poll()};return b}))}"
	"const sr=await fetch('/api/status'+q());if(gone(sr))return;"
	"const s=await sr.json();"
	"setText(statusEl,s.status||t('Idle'));dotEl.style.background=TONE[s.tone]||COL.grey;"
	"say(s.tone==='error'?'error:'+s.status:s.tone,statusEl.textContent);"
	/* Lip-sync stage: same words and colours as the phone's own light.
	 * Only meaningful while a phone is connected — the plugin's lock
	 * survives disconnects, but showing it next to a "trying to reach
	 * the phone" status would read as stale. */
	"const SYNC={measuring:[t('Sync.Measuring'),COL.accent],"
	"locked:[t('Sync.Locked'),COL.live],"
	"relocking:[t('Sync.Relocking'),COL.amber]};"
	"const sy=s.connected?SYNC[s.sync]:null;"
	"syncpillEl.style.display=sy?'':'none';"
	"if(sy){setText(syncEl,sy[0]);syncdotEl.style.background=sy[1];"
	"recalEl.style.display=s.sync==='locked'?'':'none'}"
	/* Live controls only when a camera stream is actually connected;
	 * standby gets the Start panel; screen mirror gets the note; not
	 * connected shows just the status pill. */
	"panelEl.style.display=(s.connected&&!s.screen&&!s.standby)?'':'none';"
	"show(probtnEl,s.connected&&!s.screen&&!s.standby);"
	"show(proinfoEl,s.connected&&!s.screen&&!s.standby);"
	"screennoteEl.style.display=s.screen?'':'none';"
	"startpanelEl.style.display=(s.standby&&!s.screen)?'':'none';"
	"const unarmed=s.standby&&s.armed===false;"
	"startbtnEl.style.display=unarmed?'none':'';"
	"starthintEl.style.display=unarmed?'none':'';"
	"armhintEl.style.display=unarmed?'':'none';"
	"if(typeof s.autoStart==='boolean'&&Date.now()-lastTouch>2000)"
	"asUI(s.autoStart);"
	"if(s.screen||s.standby||!s.connected)return;"
	"const str=await fetch('/api/state'+q());if(gone(str))return;"
	"const st=await str.json();"
	"if(pro){proLive(s);if(Date.now()-hLast>2000)proStill()}"
	/* Don't fight the operator's hand: only mirror app state when the panel
	 * hasn't been touched for a couple of seconds. */
	"if(Date.now()-lastTouch>2000&&typeof st.zoom==='number'){S=st;"
	"if(typeof S.paused==='boolean')pauseUI(S.paused);"
	"if(S.maxZoom)zoomEl.max=S.maxZoom;"
	"show(zoomrowEl,!(S.maxZoom<=1));zoomEl.value=S.zoom;lensUI();"
	"trayUI();flUI();"
	/* Green screen, mirrored from the app. */
	"show(gsEl,!!S.supportsGreenScreen);"
	"const gd=!!(S.supportsGreenScreen&&S.greenScreenDepth);show(gsdrowEl,gd);"
	"if(S.supportsGreenScreen){gsUI(!!S.greenScreen);"
	"let md=typeof S.greenScreenMaxDistance==='number'"
	"?S.greenScreenMaxDistance:0;"
	"md=md<0?-1:md<0.5?0:Math.min(md,5);"
	"if(md>=0)gsdEl.value=md||5.5;gsdvEl.textContent=gsLabel(md);"
	"vt(gsdEl,gsdvEl.textContent)}"
	/* Mic picker, only while the phone mic is live as source audio.
	 * Options are {id,name} pairs: ids round-trip, names display. */
	"show(microwEl,!!S.micEnabled);"
	"if(S.micEnabled&&Array.isArray(S.mics)){const mn={};"
	"S.mics.forEach(m=>mn[m.id]=m.name);"
	"fillSel(micselEl,S.mics.map(m=>m.id),S.mic,i=>mn[i]||i)}"
	/* Format pickers, populated from the app's capability lists. */
	"if(Array.isArray(S.resolutions)&&Array.isArray(S.frameRates)){"
	"show(fmtrowEl,true);"
	"fillSel(fmtresEl,S.resolutions,S.resolution);"
	"fillSel(fmtfpsEl,S.frameRates.map(String),String(S.fps),f=>f+' fps');"
	"const codecs=Array.isArray(S.codecs)?S.codecs:[];"
	"show(fmtcodecEl,codecs.length>1);"
	"fillSel(fmtcodecEl,codecs,S.codec,c=>CODEC_NAMES[c]||c);"
	"const cols=Array.isArray(S.colors)?S.colors:[];show(fmtcolorEl,cols.length>1);"
	"if(cols.length>1)fillSel(fmtcolorEl,cols,S.color||(S.hdr?'hlg':'sdr'),c=>COLORS[c]||c);"
	"show(fmtqEl,typeof S.quality==='string');"
	"if(typeof S.quality==='string')fillSel(fmtqEl,['balanced','maximum'],S.quality,"
	"x=>x==='balanced'?t('Bitrate.Stable'):t('Bitrate.Maximum'))}"
	"monUI();"
	"show(rfrowEl,!!S.supportsReframe);show(rfpadEl,!!S.supportsReframe);"
	"if(S.supportsReframe){const r=S.reframe;"
	"RF=r?{zoom:+r.zoom||1,x:+r.x||.5,y:+r.y||.5}:{zoom:1,x:.5,y:.5};rfUI();"
	"show(rfhqrowEl,!!(S.supportsReframeHQ||S.reframeHQ));hqUI(!!S.reframeHQ);"
	"if(!rfBg&&!rfZoomed&&Date.now()-rfTry>5000)rfStill()}"
	"blUI();"
	"show(stabrowEl,typeof S.stabilization==='string');"
	"show($('afrow'),typeof S.antiFlicker==='string');"
	"if(typeof S.antiFlicker==='string')"
	"fillSel(afEl,['auto','50','60'],S.antiFlicker,m=>m==='auto'?t('Auto'):m+' Hz');"
	"if(typeof S.stabilization==='string'){"
	"fillSel(stabEl,Object.keys(STAB),S.stabilization,m=>STAB[m]);"
	"stabEl.disabled=!!S.greenScreenDepth}}"
	"}catch(e){setText(statusEl,t('Unreachable'));say('unreachable',t('Unreachable'));"
	"dotEl.style.background=COL.grey}}"
	"gsUI(false);asUI(false);trayUI();proUI();pullUI();"
	"setInterval(poll,1000);poll();"
	"</script></body></html>";

struct web_control {
	pthread_t thread;
	volatile bool stop;
	socket_t listener;
	uint16_t port;
	bool lan;
};

/* One server, many sources. The registry maps small stable ids (what
 * ?src= carries) to live sources; handlers resolve a source and use it
 * entirely under the mutex, so once unregister returns, no request can
 * touch that source again. Registration happens on the UI thread;
 * lookups on the (single) web thread. */
#define WC_MAX_SOURCES 16

static struct {
	pthread_mutex_t mutex;
	struct web_control *server;
	struct {
		int id;
		struct ios_camera_source *src;
	} entries[WC_MAX_SOURCES];
	size_t count;
	int next_id;
} g_reg = {.mutex = PTHREAD_MUTEX_INITIALIZER, .next_id = 1};

/* Looks for src=<id> among the query parameters of the request target
 * (request line only). Returns 0 when absent, 1 with *id set, -1 when
 * malformed: empty, not a non-negative integer, out of range, or given
 * twice. */
static int parse_src_param(const char *request, int *id)
{
	const char *sp = strchr(request, ' ');
	if (!sp)
		return 0;
	const char *target = sp + 1;
	const char *end = target + strcspn(target, " \r\n");
	const char *p = memchr(target, '?', (size_t)(end - target));
	int found = 0;
	while (p && p < end) {
		p++;
		const char *amp = memchr(p, '&', (size_t)(end - p));
		const char *stop = amp ? amp : end;
		if (stop - p >= 4 && strncmp(p, "src=", 4) == 0) {
			const char *d = p + 4;
			int v = 0;
			if (found || d == stop)
				return -1;
			for (; d < stop; d++) {
				if (*d < '0' || *d > '9')
					return -1;
				if (v > (INT_MAX - (*d - '0')) / 10)
					return -1;
				v = v * 10 + (*d - '0');
			}
			*id = v;
			found = 1;
		}
		p = amp;
	}
	return found;
}

enum pick_result { PICK_OK, PICK_NONE, PICK_UNKNOWN, PICK_BAD };

/* ?src=<id> picks a source; without it the first registered source is
 * used, so single-source setups and scripts written before multi-source
 * keep working unchanged. An explicit id that is malformed or names no
 * source picks nothing: acting on another phone instead would be worse
 * than failing. Caller holds g_reg.mutex. */
static enum pick_result locked_pick_source(const char *request,
					   struct ios_camera_source **out)
{
	int id = 0;
	int has = parse_src_param(request, &id);

	*out = NULL;
	if (has < 0)
		return PICK_BAD;
	if (!g_reg.count)
		return PICK_NONE;
	if (!has) {
		*out = g_reg.entries[0].src;
		return PICK_OK;
	}
	for (size_t i = 0; i < g_reg.count; i++) {
		if (g_reg.entries[i].id == id) {
			*out = g_reg.entries[i].src;
			return PICK_OK;
		}
	}
	return PICK_UNKNOWN;
}

static void send_bytes(socket_t s, const char *p, size_t len)
{
	while (len > 0) {
		int n = (int)send(s, p, (int)len, 0);
		if (n <= 0)
			return;
		p += n;
		len -= (size_t)n;
	}
}

static void send_str(socket_t s, const char *str)
{
	send_bytes(s, str, strlen(str));
}

static void respond_len(socket_t s, const char *status_line,
			const char *content_type, const char *body,
			size_t len)
{
	char header[320];
	snprintf(header, sizeof(header),
		 "HTTP/1.1 %s\r\n"
		 "Content-Type: %s\r\n"
		 "Content-Length: %zu\r\n"
		 "Cache-Control: no-store\r\n"
		 "X-Frame-Options: DENY\r\n"
		 "Connection: close\r\n\r\n",
		 status_line, content_type, len);
	send_str(s, header);
	if (body)
		send_bytes(s, body, len);
}

static void respond(socket_t s, const char *status_line,
		    const char *content_type, const char *body)
{
	respond_len(s, status_line, content_type, body,
		    body ? strlen(body) : 0);
}

static void respond_pick_error(socket_t s, enum pick_result pick)
{
	if (pick == PICK_BAD)
		respond(s, "400 Bad Request", "application/json",
			"{\"error\":\"bad src\"}");
	else if (pick == PICK_UNKNOWN)
		respond(s, "404 Not Found", "application/json",
			"{\"error\":\"unknown source\"}");
	else
		respond(s, "503 Service Unavailable", "text/plain",
			"no sources");
}

/* Case-insensitive header lookup; returns pointer past "name:". */
static const char *find_header(const char *request, const char *name)
{
	size_t name_len = strlen(name);
	for (const char *p = request; (p = strchr(p, '\n')) != NULL;) {
		p++;
		size_t i = 0;
		while (i < name_len && p[i] &&
		       tolower((unsigned char)p[i]) ==
			       tolower((unsigned char)name[i]))
			i++;
		if (i == name_len && p[i] == ':')
			return p + name_len + 1;
	}
	return NULL;
}

static void json_escape(const char *in, char *out, size_t out_size)
{
	size_t o = 0;
	for (size_t i = 0; in[i] && o + 2 < out_size; i++) {
		unsigned char ch = (unsigned char)in[i];
		if (ch == '"' || ch == '\\') {
			out[o++] = '\\';
			out[o++] = (char)ch;
		} else if (ch < 0x20) {
			out[o++] = ' ';
		} else {
			out[o++] = (char)ch;
		}
	}
	out[o] = 0;
}

static void json_cat_escaped(struct dstr *d, const char *in)
{
	for (const unsigned char *p = (const unsigned char *)in; *p; p++) {
		unsigned char ch = *p;
		if (ch == '"' || ch == '\\') {
			char esc[3] = {'\\', (char)ch, 0};
			dstr_cat(d, esc);
		} else if (ch < 0x20 || ch == '<' || ch == '>' || ch == '&') {
			dstr_catf(d, "\\u%04x", (unsigned)ch);
		} else if (ch == 0xE2 && p[1] == 0x80 &&
			   (p[2] == 0xA8 || p[2] == 0xA9)) {
			dstr_cat(d, p[2] == 0xA8 ? "\\u2028" : "\\u2029");
			p += 2;
		} else {
			dstr_ncat(d, (const char *)p, 1);
		}
	}
}

static void page_lang(char *out, size_t size)
{
	const char *loc = obs_get_locale();
	size_t o = 0;
	for (; loc && *loc && o + 1 < size; loc++) {
		char c = *loc;
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
		    (c >= '0' && c <= '9') || c == '-')
			out[o++] = c;
		else if (c == '_')
			out[o++] = '-';
	}
	out[o] = 0;
	if (!o)
		snprintf(out, size, "en");
}

static pthread_mutex_t g_page_mutex = PTHREAD_MUTEX_INITIALIZER;
static char *g_page;

static const char *web_page(void)
{
	pthread_mutex_lock(&g_page_mutex);
	if (!g_page) {
		char lang[32];
		size_t prefix = strlen(WEB_KEY_PREFIX);
		size_t count = sizeof(web_text_keys) / sizeof(web_text_keys[0]);
		struct dstr d = {0};

		page_lang(lang, sizeof(lang));
		dstr_copy(&d, "<!doctype html><html lang='");
		dstr_cat(&d, lang);
		dstr_cat(&d, "'><head><meta charset='utf-8'><script>const T={");
		for (size_t i = 0; i < count; i++) {
			const char *key = web_text_keys[i];
			const char *text = obs_module_text(key);
			bool prefixed = strncmp(key, WEB_KEY_PREFIX, prefix) == 0;
			if (i)
				dstr_cat(&d, ",");
			dstr_cat(&d, "\"");
			json_cat_escaped(&d, prefixed ? key + prefix : key);
			dstr_cat(&d, "\":\"");
			json_cat_escaped(&d, text ? text : key);
			dstr_cat(&d, "\"");
		}
		dstr_cat(&d, "};</script>");
		dstr_cat(&d, control_page);
		g_page = d.array;
	}
	const char *page = g_page;
	pthread_mutex_unlock(&g_page_mutex);
	return page;
}

static const char *tone_name(enum ios_camera_status_tone tone)
{
	switch (tone) {
	case STATUS_TONE_WAIT:
		return "wait";
	case STATUS_TONE_READY:
		return "ready";
	case STATUS_TONE_LIVE:
		return "live";
	case STATUS_TONE_ERROR:
		return "error";
	case STATUS_TONE_IDLE:
	default:
		return "idle";
	}
}

static enum web_auth_result request_auth(const char *request,
					 bool peer_loopback, bool lan)
{
	char key[WEB_AUTH_KEY_SIZE];
	lenslink_settings_web_key(key, sizeof(key));
	return web_auth_check(find_header(request, "Host"),
			      find_header(request, "Origin"),
			      find_header(request, "Cookie"), request,
			      peer_loopback, lan, key);
}

static void respond_login(socket_t s)
{
	char key[WEB_AUTH_KEY_SIZE], header[320];
	lenslink_settings_web_key(key, sizeof(key));
	snprintf(header, sizeof(header),
		 "HTTP/1.1 302 Found\r\n"
		 "Location: /\r\n"
		 "Set-Cookie: ll_key=%s; Path=/; SameSite=Strict; HttpOnly\r\n"
		 "Content-Length: 0\r\n"
		 "Cache-Control: no-store\r\n"
		 "X-Frame-Options: DENY\r\n"
		 "Connection: close\r\n\r\n",
		 key);
	send_str(s, header);
}

static int recv_by(socket_t s, char *buf, int len, uint64_t deadline)
{
	uint64_t now = os_gettime_ns();
	if (now >= deadline)
		return -1;
	int ms = (int)((deadline - now) / 1000000ULL) + 1;
	if (net_wait(s, NET_WAIT_READ, ms) <= 0)
		return -1;
	return (int)recv(s, buf, len, 0);
}

static bool json_object_complete(const char *body, size_t len)
{
	struct json_reader r;
	lenslink_json_reader_init(&r, body, len);
	return lenslink_json_peek(&r) == JSON_TYPE_OBJECT &&
	       lenslink_json_skip(&r) && lenslink_json_reader_done(&r);
}

static bool parse_autostart_body(const char *body, size_t len, bool *on)
{
	struct json_reader r;
	char key[16];
	bool truncated, found = false;
	lenslink_json_reader_init(&r, body, len);
	if (!lenslink_json_object_begin(&r))
		return false;
	while (lenslink_json_object_next(&r, key, sizeof(key), &truncated)) {
		if (!truncated && strcmp(key, "on") == 0 &&
		    lenslink_json_read_bool(&r, on))
			found = true;
		else if (!lenslink_json_skip(&r))
			return false;
	}
	return found && lenslink_json_reader_done(&r);
}

static void handle_client(socket_t client, bool peer_loopback, bool lan)
{
	uint64_t deadline = os_gettime_ns() + REQUEST_DEADLINE_NS;
	char request[MAX_REQUEST + 1];
	size_t have = 0;
	const char *body = NULL;

	/* On Windows the accepted socket inherits the listener's
	 * non-blocking mode; this handler needs blocking reads. */
	net_set_blocking(client);
	net_set_timeouts(client, 2);

	/* Read until end of headers. */
	while (have < MAX_REQUEST) {
		int n = recv_by(client, request + have,
				(int)(MAX_REQUEST - have), deadline);
		if (n <= 0)
			return;
		have += (size_t)n;
		request[have] = 0;
		const char *end = strstr(request, "\r\n\r\n");
		if (end) {
			body = end + 4;
			break;
		}
	}
	if (!body)
		return;

	enum web_auth_result auth = request_auth(request, peer_loopback, lan);
	if (auth == WEB_AUTH_DENY) {
		respond(client, "403 Forbidden", "text/plain", "forbidden");
		return;
	}
	if (auth == WEB_AUTH_OK_QUERY_KEY &&
	    (strncmp(request, "GET / ", 6) == 0 ||
	     strncmp(request, "GET /?", 6) == 0)) {
		respond_login(client);
		return;
	}

	/* For POSTs, pull the whole body in before touching the source
	 * registry — a slow client must never stall register/unregister
	 * (the OBS UI thread) on our socket reads. */
	size_t body_offset = (size_t)(body - request);
	size_t content_length = 0;
	if (strncmp(request, "POST ", 5) == 0) {
		const char *cl = find_header(request, "Content-Length");
		if (cl && !web_auth_content_length(cl, MAX_CONTROL_BODY,
						   &content_length)) {
			respond(client, "400 Bad Request", "text/plain",
				"bad length");
			return;
		}
		/* A zero-length body is legal here: action-only endpoints
		 * (/api/recalibrate) POST with no body at all, and rejecting
		 * that generically 400'd them before routing — the panel's
		 * Recalibrate button died of exactly that. Endpoints that
		 * *need* a body enforce it themselves below. */
		while (have - body_offset < content_length &&
		       have < MAX_REQUEST) {
			int n = recv_by(client, request + have,
					(int)(MAX_REQUEST - have), deadline);
			if (n <= 0)
				return;
			have += (size_t)n;
			request[have] = 0;
		}
		/* The refill loop can also exit because the buffer is full
		 * (headers padded near MAX_REQUEST); enqueuing then would
		 * read past the received bytes — off the end of `request`. */
		if (have - body_offset < content_length) {
			respond(client, "400 Bad Request", "text/plain",
				"truncated body");
			return;
		}
	}

	if (strncmp(request, "GET / ", 6) == 0) {
		respond(client, "200 OK", "text/html; charset=utf-8",
			web_page());
		return;
	}

	/* Plain text, so "curl localhost:9980/api/diagnostics" is a
	 * complete bug report without a Qt build or a mouse. */
	if (strncmp(request, "GET /api/diagnostics", 20) == 0) {
		char *report = lenslink_diagnostics_report();
		respond(client, "200 OK", "text/plain; charset=utf-8", report);
		bfree(report);
		return;
	}

	if (strncmp(request, "GET /api/sources", 16) == 0) {
		char json[4096];
		size_t o = (size_t)snprintf(json, sizeof(json),
					    "{\"sources\":[");
		pthread_mutex_lock(&g_reg.mutex);
		for (size_t i = 0; i < g_reg.count && o + 384 < sizeof(json);
		     i++) {
			struct ios_camera_source *s = g_reg.entries[i].src;
			char name[128], esc[280];
			ios_camera_copy_name(s, name, sizeof(name));
			json_escape(name, esc, sizeof(esc));
			o += (size_t)snprintf(
				json + o, sizeof(json) - o,
				"%s{\"id\":%d,\"name\":\"%s\","
				"\"connected\":%s,\"standby\":%s,"
				"\"armed\":%s,\"screen\":%s}",
				i ? "," : "", g_reg.entries[i].id, esc,
				ios_camera_is_connected(s) ? "true" : "false",
				ios_camera_is_standby(s) ? "true" : "false",
				ios_camera_is_armed(s) ? "true" : "false",
				ios_camera_is_screen(s) ? "true" : "false");
		}
		pthread_mutex_unlock(&g_reg.mutex);
		snprintf(json + o, sizeof(json) - o, "]}");
		respond(client, "200 OK", "application/json", json);
		return;
	}

	if (strncmp(request, "GET /api/state", 14) == 0) {
		/* Must fit the source's whole device_state cache (32 KB cap) —
		 * truncation here would hand the panel unparsable JSON. */
		char state[32 * 1024 + 1] = {0};
		struct ios_camera_source *s = NULL;
		pthread_mutex_lock(&g_reg.mutex);
		enum pick_result pick = locked_pick_source(request, &s);
		if (s)
			ios_camera_copy_state(s, state, sizeof(state));
		pthread_mutex_unlock(&g_reg.mutex);
		if (!s) {
			respond_pick_error(client, pick);
			return;
		}
		respond(client, "200 OK", "application/json", state);
		return;
	}

	if (strncmp(request, "GET /api/status", 15) == 0) {
		char status[1024] = {0};
		char escaped[2048] = {0};
		char json[2560];
		enum ios_camera_status_tone tone = STATUS_TONE_IDLE;
		struct ios_camera_live live = {.audio_peak = -1};
		bool screen = false, standby = false, connected = false;
		bool armed = false, auto_start = false;
		const char *sync = "off";

		struct ios_camera_source *s = NULL;
		pthread_mutex_lock(&g_reg.mutex);
		enum pick_result pick = locked_pick_source(request, &s);
		if (s) {
			ios_camera_copy_status(s, status, sizeof(status),
					       &tone);
			screen = ios_camera_is_screen(s);
			standby = ios_camera_is_standby(s);
			armed = ios_camera_is_armed(s);
			connected = ios_camera_is_connected(s);
			auto_start = ios_camera_auto_start(s);
			sync = ios_camera_sync_state(s);
			ios_camera_live_stats(s, &live);
		}
		pthread_mutex_unlock(&g_reg.mutex);
		if (!s) {
			respond_pick_error(client, pick);
			return;
		}
		json_escape(status, escaped, sizeof(escaped));
		snprintf(json, sizeof(json),
			 "{\"status\":\"%s\",\"tone\":\"%s\",\"screen\":%s,"
			 "\"standby\":%s,\"armed\":%s,\"connected\":%s,"
			 "\"autoStart\":%s,\"sync\":\"%s\",\"latencyMs\":%d,"
			 "\"bytes\":%llu,\"sampleMs\":%llu,\"liveMs\":%llu,"
			 "\"audioPeak\":%d}",
			 escaped, tone_name(tone), screen ? "true" : "false",
			 standby ? "true" : "false", armed ? "true" : "false",
			 connected ? "true" : "false",
			 auto_start ? "true" : "false", sync, live.latency_ms,
			 (unsigned long long)live.bytes,
			 (unsigned long long)live.sample_ms,
			 (unsigned long long)live.live_ms, live.audio_peak);
		respond(client, "200 OK", "application/json", json);
		return;
	}

	if (strncmp(request, "POST /api/autostart", 19) == 0) {
		/* Body: {"on":true|false}. Toggles the source's auto-start
		 * property (same value the properties checkbox edits). An
		 * empty body must not silently read as "false". */
		if (content_length == 0) {
			respond(client, "400 Bad Request", "text/plain",
				"body required");
			return;
		}
		bool on = false;
		if (!parse_autostart_body(request + body_offset, content_length,
					  &on)) {
			respond(client, "400 Bad Request", "text/plain",
				"bad body");
			return;
		}
		struct ios_camera_source *s = NULL;
		pthread_mutex_lock(&g_reg.mutex);
		enum pick_result pick = locked_pick_source(request, &s);
		if (s)
			ios_camera_set_auto_start(s, on);
		pthread_mutex_unlock(&g_reg.mutex);
		if (!s)
			respond_pick_error(client, pick);
		else
			respond(client, "204 No Content", "text/plain", NULL);
		return;
	}

	if (strncmp(request, "POST /api/recalibrate", 21) == 0) {
		/* Drops the locked lip-sync mic figure and measures afresh —
		 * the panel's Recalibrate button. No body. */
		struct ios_camera_source *s = NULL;
		pthread_mutex_lock(&g_reg.mutex);
		enum pick_result pick = locked_pick_source(request, &s);
		if (s)
			ios_camera_recalibrate(s);
		pthread_mutex_unlock(&g_reg.mutex);
		if (!s)
			respond_pick_error(client, pick);
		else
			respond(client, "204 No Content", "text/plain", NULL);
		return;
	}

	if (strncmp(request, "POST /api/still", 15) == 0 ||
	    strncmp(request, "GET /api/still", 14) == 0) {
		bool post = request[0] == 'P';
		uint8_t *still = NULL;
		size_t len = 0;
		struct ios_camera_source *s = NULL;
		pthread_mutex_lock(&g_reg.mutex);
		enum pick_result pick = locked_pick_source(request, &s);
		if (s && post)
			ios_camera_request_still(s);
		else if (s)
			still = ios_camera_take_still(s, &len);
		pthread_mutex_unlock(&g_reg.mutex);
		if (!s)
			respond_pick_error(client, pick);
		else if (still)
			respond_len(client, "200 OK", "image/bmp",
				    (const char *)still, len);
		else
			respond(client, "204 No Content", "text/plain", NULL);
		free(still);
		return;
	}

	if (strncmp(request, "POST /api/control", 17) == 0) {
		if (content_length == 0) {
			respond(client, "400 Bad Request", "text/plain",
				"body required");
			return;
		}
		if (!json_object_complete(request + body_offset,
					  content_length)) {
			respond(client, "400 Bad Request", "text/plain",
				"bad body");
			return;
		}
		struct ios_camera_source *s = NULL;
		pthread_mutex_lock(&g_reg.mutex);
		enum pick_result pick = locked_pick_source(request, &s);
		if (s)
			ios_camera_enqueue_control(s, request + body_offset,
						   content_length);
		pthread_mutex_unlock(&g_reg.mutex);
		if (!s)
			respond_pick_error(client, pick);
		else
			respond(client, "204 No Content", "text/plain", NULL);
		return;
	}

	respond(client, "404 Not Found", "text/plain", "not found");
}

static void *web_thread(void *data)
{
	struct web_control *wc = data;

	os_set_thread_name("ios-camera-web");

	while (!wc->stop) {
		int ret = net_wait(wc->listener, NET_WAIT_READ, 200);
		if (ret < 0)
			break;
		if (ret == 0)
			continue;

		struct sockaddr_in from;
		socklen_t from_len = sizeof(from);
		socket_t client = accept(wc->listener,
					 (struct sockaddr *)&from, &from_len);
		if (client == OBSC_INVALID_SOCKET)
			continue;

		handle_client(client,
			      (ntohl(from.sin_addr.s_addr) >> 24) == 127,
			      wc->lan);
		net_close(client);
	}

	return NULL;
}

static struct web_control *server_start(uint16_t port, bool lan)
{
	socket_t listener = socket(AF_INET, SOCK_STREAM, 0);
	if (listener == OBSC_INVALID_SOCKET)
		return NULL;

	int yes = 1;
	setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, (const char *)&yes,
		   sizeof(yes));

	/* Local machine only unless LAN access is on — this is a control
	 * surface. */
	struct sockaddr_in addr = {0};
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(lan ? INADDR_ANY : INADDR_LOOPBACK);
	addr.sin_port = htons(port);

	if (bind(listener, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
	    listen(listener, 4) != 0) {
		blog(LOG_WARNING,
		     "[lenslink] web control: port %u unavailable — is "
		     "another app using it? The port can be changed in "
		     "Tools → LensLink Settings",
		     (unsigned)port);
		net_close(listener);
		return NULL;
	}

	net_set_nonblocking(listener);

	struct web_control *wc = bzalloc(sizeof(*wc));
	wc->listener = listener;
	wc->port = port;
	wc->lan = lan;

	if (pthread_create(&wc->thread, NULL, web_thread, wc) != 0) {
		net_close(listener);
		bfree(wc);
		return NULL;
	}

	blog(LOG_INFO,
	     "[lenslink] web control panel at http://localhost:%u/%s",
	     (unsigned)port, lan ? " (and on the local network, key required)"
				 : "");
	return wc;
}

static void server_stop(struct web_control *wc)
{
	if (!wc)
		return;
	wc->stop = true;
	pthread_join(wc->thread, NULL);
	net_close(wc->listener);
	bfree(wc);
}

/* Reconcile the singleton server with the plugin-wide settings and the
 * registry: running while (enabled && any source), on the settings'
 * port. The server to stop is detached under the mutex but joined
 * outside it — a request handler blocked on g_reg.mutex must be able to
 * finish, or the join would deadlock. */
void web_control_apply_settings(void)
{
	struct web_control *to_stop = NULL;
	uint16_t port = (uint16_t)lenslink_settings_web_port();
	bool lan = lenslink_settings_web_lan();

	pthread_mutex_lock(&g_reg.mutex);
	bool want = lenslink_settings_web_enabled() && g_reg.count > 0;
	if (g_reg.server && (!want || g_reg.server->port != port ||
			     g_reg.server->lan != lan)) {
		to_stop = g_reg.server;
		g_reg.server = NULL;
	}
	bool need_start = want && !g_reg.server;
	pthread_mutex_unlock(&g_reg.mutex);

	if (to_stop)
		server_stop(to_stop);
	if (!need_start)
		return;

	struct web_control *wc = server_start(port, lan);
	if (!wc)
		return;
	pthread_mutex_lock(&g_reg.mutex);
	if (!g_reg.server && g_reg.count > 0) {
		g_reg.server = wc;
		wc = NULL;
	}
	pthread_mutex_unlock(&g_reg.mutex);
	if (wc) /* raced with another apply, or the registry emptied */
		server_stop(wc);
}

void web_control_register(struct ios_camera_source *source)
{
	pthread_mutex_lock(&g_reg.mutex);
	for (size_t i = 0; i < g_reg.count; i++) {
		if (g_reg.entries[i].src == source) {
			pthread_mutex_unlock(&g_reg.mutex);
			return;
		}
	}
	if (g_reg.count < WC_MAX_SOURCES) {
		g_reg.entries[g_reg.count].id = g_reg.next_id++;
		g_reg.entries[g_reg.count].src = source;
		g_reg.count++;
	} else {
		blog(LOG_WARNING,
		     "[lenslink] web control: more than %d sources; "
		     "extra sources won't appear in the panel",
		     WC_MAX_SOURCES);
	}
	pthread_mutex_unlock(&g_reg.mutex);
}

void web_control_unregister(struct ios_camera_source *source)
{
	pthread_mutex_lock(&g_reg.mutex);
	for (size_t i = 0; i < g_reg.count; i++) {
		if (g_reg.entries[i].src == source) {
			memmove(&g_reg.entries[i], &g_reg.entries[i + 1],
				(g_reg.count - i - 1) *
					sizeof(g_reg.entries[0]));
			g_reg.count--;
			break;
		}
	}
	pthread_mutex_unlock(&g_reg.mutex);
}

void web_control_shutdown(void)
{
	pthread_mutex_lock(&g_reg.mutex);
	struct web_control *to_stop = g_reg.server;
	g_reg.server = NULL;
	pthread_mutex_unlock(&g_reg.mutex);
	server_stop(to_stop);

	pthread_mutex_lock(&g_page_mutex);
	bfree(g_page);
	g_page = NULL;
	pthread_mutex_unlock(&g_page_mutex);
}
