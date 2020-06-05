// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bTileLinkMap
{
    uint2 iTileLinkMap[1];
};

struct bInitialTileMap
{
    uint iInitialTileMap[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 16u, 1u);

static inline __attribute__((always_inline))
void sortedInsert(thread uint& headIndex, thread const uint& newNodeIndex, device bTileLinkMap& v_31)
{
    if ((headIndex == 4294967295u) || (headIndex >= newNodeIndex))
    {
        v_31.iTileLinkMap[newNodeIndex].y = headIndex;
        headIndex = newNodeIndex;
        return;
    }
    uint currentNodeIndex = headIndex;
    for (;;)
    {
        bool _51 = v_31.iTileLinkMap[currentNodeIndex].y != 4294967295u;
        bool _59;
        if (_51)
        {
            _59 = v_31.iTileLinkMap[currentNodeIndex].y < newNodeIndex;
        }
        else
        {
            _59 = _51;
        }
        if (_59)
        {
            currentNodeIndex = v_31.iTileLinkMap[currentNodeIndex].y;
            continue;
        }
        else
        {
            break;
        }
    }
    v_31.iTileLinkMap[newNodeIndex].y = v_31.iTileLinkMap[currentNodeIndex].y;
    v_31.iTileLinkMap[currentNodeIndex].y = newNodeIndex;
}

static inline __attribute__((always_inline))
void insertionSort(thread uint& headIndex, device bTileLinkMap& v_31)
{
    uint sortedHeadIndex = 4294967295u;
    uint currentNodeIndex = headIndex;
    while (currentNodeIndex != 4294967295u)
    {
        uint nextNodeIndex = v_31.iTileLinkMap[currentNodeIndex].y;
        uint param = sortedHeadIndex;
        uint param_1 = currentNodeIndex;
        sortedInsert(param, param_1, v_31);
        sortedHeadIndex = param;
        currentNodeIndex = nextNodeIndex;
    }
    headIndex = sortedHeadIndex;
}

kernel void main0(constant int2& uFramebufferTileSize [[buffer(1)]], device bTileLinkMap& v_31 [[buffer(0)]], device bInitialTileMap& _138 [[buffer(2)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    int2 tileCoords = int2(gl_GlobalInvocationID.xy);
    bool _111 = tileCoords.x >= uFramebufferTileSize.x;
    bool _120;
    if (!_111)
    {
        _120 = tileCoords.y >= uFramebufferTileSize.y;
    }
    else
    {
        _120 = _111;
    }
    if (_120)
    {
        return;
    }
    uint tileMapIndex = uint(tileCoords.x + (tileCoords.y * uFramebufferTileSize.x));
    uint headIndex = _138.iInitialTileMap[tileMapIndex];
    uint param = headIndex;
    insertionSort(param, v_31);
    headIndex = param;
    _138.iInitialTileMap[tileMapIndex] = headIndex;
}

