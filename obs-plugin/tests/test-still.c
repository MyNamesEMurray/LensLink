#include "test.h"
#include "still.h"

#include <stdlib.h>

static uint32_t le32(const uint8_t *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

int main(void)
{
	/* 8x4 NV12, limited range: left half white, right half black. */
	uint8_t y[32], uv[16];
	for (int i = 0; i < 32; i++)
		y[i] = (i % 8) < 4 ? 235 : 16;
	memset(uv, 128, sizeof(uv));
	struct still_src src = {.layout = STILL_NV12, .width = 8, .height = 4,
				.data = {y, uv}, .linesize = {8, 8}};

	size_t len = 0;
	uint8_t *bmp = still_bmp(&src, 4, &len);
	CHECK(bmp != NULL);
	CHECK(bmp[0] == 'B' && bmp[1] == 'M');
	CHECK(le32(bmp + 18) == 4);
	CHECK(le32(bmp + 22) == 2);
	CHECK(len == 54 + 12 * 2);
	CHECK(le32(bmp + 2) == len);
	/* Bottom-up rows; each row: white, white, black, black. */
	const uint8_t *row = bmp + 54;
	CHECK(row[0] == 255 && row[1] == 255 && row[2] == 255);
	CHECK(row[6] == 0 && row[7] == 0 && row[8] == 0);
	free(bmp);

	/* Smaller than max_w keeps its size; red in full-range I420. */
	uint8_t yy[4] = {76, 76, 76, 76}, u[1] = {85}, v[1] = {255};
	struct still_src red = {.layout = STILL_I420, .width = 2, .height = 2,
				.data = {yy, u, v}, .linesize = {2, 1, 1},
				.full_range = true};
	bmp = still_bmp(&red, 480, &len);
	CHECK(bmp != NULL && le32(bmp + 18) == 2);
	CHECK(bmp[54 + 2] > 240 && bmp[54 + 1] < 40 && bmp[54] < 20);
	free(bmp);

	CHECK(still_bmp(NULL, 480, &len) == NULL);
	src.width = 0;
	CHECK(still_bmp(&src, 480, &len) == NULL);

	TEST_MAIN_END();
}
