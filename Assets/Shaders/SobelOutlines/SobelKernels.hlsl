#ifndef SOBEL_KERNELS_INCLUDED
#define SOBEL_KERNELS_INCLUDED

static const float2 k_samples[9] =
{
    float2(-1.0, 1.0), float2(0.0, 1.0), float2(1.0, 1.0),
    float2(-1.0, 0.0), float2(0.0, 0.0), float2(1.0, 0.0),
    float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0)
};

static const float k_sobel_x[9] =
{
    1.0, 0.0, -1.0,
    2.0, 0.0, -2.0,
    1.0, 0.0, -1.0
};

static const float k_sobel_y[9] =
{
    1.0, 2.0, 1.0,
    0.0, 0.0, 0.0,
    -1.0, -2.0, -1.0
};

#endif
