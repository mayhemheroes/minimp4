/*
 * mayhem/fuzz_minimp4.c — in-process libFuzzer harness for minimp4's H.264/H.265 -> MP4
 * muxing path (MP4E_* / mp4_h26x_write_*).
 *
 * This drives EXACTLY the code path the archived Mayhem target `minimp4-x86` exercised — the
 * upstream `minimp4_test -m <in> <out>` mux command (do_demux=0): read an H.264 elementary
 * stream, split it into NAL units, and feed each NAL to the muxer. The archived target ran the
 * raw CLI binary (uninstrumented, black-box, writing to a file); this replaces it with an
 * instrumented in-process harness over the same API so libFuzzer/Mayhem get real coverage
 * feedback (SanitizerCoverage) and the fuzzed library code is ASan/UBSan-instrumented.
 *
 * The MP4E write callback targets an in-memory growable buffer (the muxer seeks backwards to
 * patch box sizes, so the sink must support random-access writes) — no disk, no absolute paths.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define MINIMP4_IMPLEMENTATION
#include "minimp4.h"

#define VIDEO_FPS 30

typedef struct {
    uint8_t *data;
    size_t   size;
    size_t   cap;
} membuf_t;

static int write_callback(int64_t offset, const void *buffer, size_t size, void *token)
{
    membuf_t *mb = (membuf_t *)token;
    if (offset < 0)
        return 1;
    size_t end = (size_t)offset + size;
    if (end < (size_t)offset) /* overflow */
        return 1;
    if (end > mb->cap) {
        size_t ncap = mb->cap ? mb->cap : 4096;
        while (ncap < end)
            ncap *= 2;
        uint8_t *n = (uint8_t *)realloc(mb->data, ncap);
        if (!n)
            return 1;
        mb->data = n;
        mb->cap = ncap;
    }
    memcpy(mb->data + offset, buffer, size);
    if (end > mb->size)
        mb->size = end;
    return 0;
}

/* NAL splitter — identical logic to minimp4_test.c's get_nal_size(). */
static ssize_t get_nal_size(uint8_t *buf, ssize_t size)
{
    ssize_t pos = 3;
    while ((size - pos) > 3) {
        if (buf[pos] == 0 && buf[pos + 1] == 0 && buf[pos + 2] == 1)
            return pos;
        if (buf[pos] == 0 && buf[pos + 1] == 0 && buf[pos + 2] == 0 && buf[pos + 3] == 1)
            return pos;
        pos++;
    }
    return size;
}

static void mux_once(const uint8_t *data, size_t size, int sequential_mode,
                     int fragmentation_mode, int is_hevc)
{
    /* Copy the input so the harness owns a mutable, exactly-sized buffer (mirrors the
     * CLI's preload() malloc; keeps ASan bounds tight around the parsed stream). */
    uint8_t *alloc_buf = (uint8_t *)malloc(size ? size : 1);
    if (!alloc_buf)
        return;
    memcpy(alloc_buf, data, size);

    uint8_t *buf_h264 = alloc_buf;
    ssize_t h264_size = (ssize_t)size;

    membuf_t mb = { NULL, 0, 0 };
    MP4E_mux_t *mux = MP4E_open(sequential_mode, fragmentation_mode, &mb, write_callback);
    if (!mux) {
        free(alloc_buf);
        return;
    }

    mp4_h26x_writer_t mp4wr;
    if (MP4E_STATUS_OK == mp4_h26x_write_init(&mp4wr, mux, 352, 288, is_hevc)) {
        while (h264_size > 0) {
            ssize_t nal_size = get_nal_size(buf_h264, h264_size);
            if (nal_size < 4) {
                buf_h264  += 1;
                h264_size -= 1;
                continue;
            }
            if (MP4E_STATUS_OK != mp4_h26x_write_nal(&mp4wr, buf_h264, (int)nal_size, 90000 / VIDEO_FPS))
                break;
            buf_h264  += nal_size;
            h264_size -= nal_size;
        }
        mp4_h26x_write_close(&mp4wr);
    }

    MP4E_close(mux);
    free(mb.data);
    free(alloc_buf);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 4)
        return 0;

    /* Use the first byte to select mux modes so a single corpus exercises the
     * plain / sequential / fragmentation writer variants + the HEVC path, without
     * changing what bytes reach the parser (the NAL stream is data[1:]). */
    uint8_t sel = data[0];
    const uint8_t *stream = data + 1;
    size_t stream_size = size - 1;

    int sequential_mode   = (sel & 1) ? 1 : 0;
    int fragmentation_mode = (sel & 2) ? 1 : 0;
    int is_hevc           = (sel & 4) ? 1 : 0;

    mux_once(stream, stream_size, sequential_mode, fragmentation_mode, is_hevc);
    return 0;
}
