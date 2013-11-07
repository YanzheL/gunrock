// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * scatter_tile.cuh
 *
 * @brief Kernel utilities for scattering data
 */

#pragma once

#include <gunrock/util/io/modified_store.cuh>
#include <gunrock/util/operators.cuh>

namespace gunrock {
namespace util {
namespace io {

/**
 * Scatter a tile of data items using the corresponding tile of scatter_offsets
 */
template <
    int LOG_LOADS_PER_TILE,                                     // Number of vector loads (log)
    int LOG_LOAD_VEC_SIZE,                                      // Number of items per vector load (log)
    int ACTIVE_THREADS,                                         // Active threads that will be loading
    st::CacheModifier CACHE_MODIFIER>                           // Cache modifier (e.g., CA/CG/CS/NONE/etc.)
struct ScatterTile
{
    enum {
        LOADS_PER_TILE              = 1 << LOG_LOADS_PER_TILE,
        LOAD_VEC_SIZE               = 1 << LOG_LOAD_VEC_SIZE,
        LOG_ELEMENTS_PER_THREAD     = LOG_LOADS_PER_TILE + LOG_LOAD_VEC_SIZE,
        ELEMENTS_PER_THREAD         = 1 << LOG_ELEMENTS_PER_THREAD,
        TILE_SIZE                   = ACTIVE_THREADS * ELEMENTS_PER_THREAD,
    };

    //---------------------------------------------------------------------
    // Helper Structures
    //---------------------------------------------------------------------

    // Iterate next vector item
    template <int LOAD, int VEC, int dummy = 0>
    struct Iterate
    {
        // Unguarded
        template <typename T, void Transform(T&), typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE])
        {
            Transform(data[LOAD][VEC]);
            ModifiedStore<CACHE_MODIFIER>::St(data[LOAD][VEC], dest + scatter_offsets[LOAD][VEC]);

            Iterate<LOAD, VEC + 1>::template Invoke<T, Transform>(
                dest, data, scatter_offsets);
        }

        // Guarded by flags
        template <typename T, void Transform(T&), typename Flag, typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            Flag valid_flags[][LOAD_VEC_SIZE])
        {
            if (valid_flags[LOAD][VEC]) {

                Transform(data[LOAD][VEC]);
                ModifiedStore<CACHE_MODIFIER>::St(data[LOAD][VEC], dest + scatter_offsets[LOAD][VEC]);
            }

            Iterate<LOAD, VEC + 1>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, valid_flags);
        }

        // Guarded by partial tile size
        template <typename T, void Transform(T&), typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            const SizeT &partial_tile_size)
        {
            int tile_rank = (threadIdx.x << LOG_LOAD_VEC_SIZE) + (LOAD * ACTIVE_THREADS * LOAD_VEC_SIZE) + VEC;

            if (tile_rank < partial_tile_size) {

                Transform(data[LOAD][VEC]);
                ModifiedStore<CACHE_MODIFIER>::St(data[LOAD][VEC], dest + scatter_offsets[LOAD][VEC]);
            }

            Iterate<LOAD, VEC + 1>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, partial_tile_size);
        }

        // Guarded by flags and partial tile size
        template <typename T, void Transform(T&), typename Flag, typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            Flag valid_flags[][LOAD_VEC_SIZE],
            const SizeT &partial_tile_size)
        {
            int tile_rank = (threadIdx.x << LOG_LOAD_VEC_SIZE) + (LOAD * ACTIVE_THREADS * LOAD_VEC_SIZE) + VEC;

            if (valid_flags[LOAD][VEC] && (tile_rank < partial_tile_size)) {

                Transform(data[LOAD][VEC]);
                ModifiedStore<CACHE_MODIFIER>::St(data[LOAD][VEC], dest + scatter_offsets[LOAD][VEC]);
            }

            Iterate<LOAD, VEC + 1>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, valid_flags, partial_tile_size);
        }
    };


    // Next Load
    template <int LOAD, int dummy>
    struct Iterate<LOAD, LOAD_VEC_SIZE, dummy>
    {
        // Unguarded
        template <typename T, void Transform(T&), typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE])
        {
            Iterate<LOAD + 1, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets);
        }

        // Guarded by flags
        template <typename T, void Transform(T&), typename Flag, typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            Flag valid_flags[][LOAD_VEC_SIZE])
        {
            Iterate<LOAD + 1, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, valid_flags);
        }

        // Guarded by partial tile size
        template <typename T, void Transform(T&), typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            const SizeT &partial_tile_size)
        {
            Iterate<LOAD + 1, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, partial_tile_size);
        }

        // Guarded by flags and partial tile size
        template <typename T, void Transform(T&), typename Flag, typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            Flag valid_flags[][LOAD_VEC_SIZE],
            const SizeT &partial_tile_size)
        {
            Iterate<LOAD + 1, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, valid_flags, partial_tile_size);
        }
    };


    // Terminate
    template <int dummy>
    struct Iterate<LOADS_PER_TILE, 0, dummy>
    {
        // Unguarded
        template <typename T, void Transform(T&), typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE]) {}

        // Guarded by flags
        template <typename T, void Transform(T&), typename Flag, typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            Flag valid_flags[][LOAD_VEC_SIZE]) {}

        // Guarded by partial tile size
        template <typename T, void Transform(T&), typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            const SizeT &partial_tile_size) {}

        // Guarded by flags and partial tile size
        template <typename T, void Transform(T&), typename Flag, typename SizeT>
        static __device__ __forceinline__ void Invoke(
            T *dest,
            T data[][LOAD_VEC_SIZE],
            SizeT scatter_offsets[][LOAD_VEC_SIZE],
            Flag valid_flags[][LOAD_VEC_SIZE],
            const SizeT &partial_tile_size) {}
    };

    //---------------------------------------------------------------------
    // Interface
    //---------------------------------------------------------------------

    /**
     * Scatter to destination with transform.  The write is
     * predicated on the element's index in
     * the tile is not exceeding the partial tile size
     */
    template <
        typename T,
        void Transform(T&),                             // Assignment function to transform the stored value
        typename SizeT>
    static __device__ __forceinline__ void Scatter(
        T *dest,
        T data[][LOAD_VEC_SIZE],
        SizeT scatter_offsets[][LOAD_VEC_SIZE],
        const SizeT &partial_tile_size = TILE_SIZE)
    {
        if (partial_tile_size < TILE_SIZE) {

            // guarded IO
            Iterate<0, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, partial_tile_size);

        } else {

            // unguarded IO
            Iterate<0, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets);
        }
    }

    /**
     * Scatter to destination.  The write is predicated on the element's index in
     * the tile is not exceeding the partial tile size
     */
    template <typename T, typename SizeT>
    static __device__ __forceinline__ void Scatter(
        T *dest,
        T data[][LOAD_VEC_SIZE],
        SizeT scatter_offsets[][LOAD_VEC_SIZE],
        const SizeT &partial_tile_size = TILE_SIZE)
    {
        Scatter<T, Operators<T>::NopTransform>(
            dest, data, scatter_offsets, partial_tile_size);
    }

    /**
     * Scatter to destination with transform.  The write is
     * predicated on valid flags and that the element's index in
     * the tile is not exceeding the partial tile size
     */
    template <
        typename T,
        void Transform(T&),                             // Assignment function to transform the stored value
        typename Flag,
        typename SizeT>
    static __device__ __forceinline__ void Scatter(
        T *dest,
        T data[][LOAD_VEC_SIZE],
        Flag flags[][LOAD_VEC_SIZE],
        SizeT scatter_offsets[][LOAD_VEC_SIZE],
        const SizeT &partial_tile_size = TILE_SIZE)
    {
        if (partial_tile_size < TILE_SIZE) {

            // guarded by flags and partial tile size
            Iterate<0, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, flags, partial_tile_size);

        } else {

            // guarded by flags
            Iterate<0, 0>::template Invoke<T, Transform>(
                dest, data, scatter_offsets, flags);
        }
    }

    /**
     * Scatter to destination.  The write is
     * predicated on valid flags and that the element's index in
     * the tile is not exceeding the partial tile size
     */
    template <typename T, typename Flag, typename SizeT>
    static __device__ __forceinline__ void Scatter(
        T *dest,
        T data[][LOAD_VEC_SIZE],
        Flag flags[][LOAD_VEC_SIZE],
        SizeT scatter_offsets[][LOAD_VEC_SIZE],
        const SizeT &partial_tile_size = TILE_SIZE)
    {
        Scatter<T, Operators<T>::NopTransform>(
            dest, data, flags, scatter_offsets, partial_tile_size);
    }

};



} // namespace io
} // namespace util
} // namespace gunrock

