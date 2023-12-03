using Oceananigans
using Oceananigans.Grids: AbstractGrid

using KernelAbstractions: @kernel, @index

import Oceananigans.Utils: active_cells_work_layout, 
                           use_only_active_interior_cells

using Oceananigans.Solvers: solve_batched_tridiagonal_system_z!, ZDirection
using Oceananigans.DistributedComputations: DistributedGrid

import Oceananigans.Solvers: solve_batched_tridiagonal_system_kernel!

const ActiveCellsIBG            = ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any, Union{<:AbstractArray, <:NamedTuple}}
const ActiveSurfaceIBG          = ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:AbstractArray}
const DistributedActiveCellsIBG = ImmersedBoundaryGrid{<:DistributedGrid, <:Any, <:Any, <:Any, <:Any, <:Any, <:NamedTuple}

struct InteriorMap end
struct SurfaceMap end

struct WestMap  end
struct EastMap  end
struct SouthMap end
struct NorthMap end

active_map(::Val{:west})  = WestMap()
active_map(::Val{:east})  = EastMap()
active_map(::Val{:south}) = SouthMap()
active_map(::Val{:north}) = NorthMap()

@inline use_only_active_surface_cells(::AbstractGrid)     = nothing
@inline use_only_active_interior_cells(::ActiveCellsIBG)  = InteriorMap()
@inline use_only_active_surface_cells(::ActiveSurfaceIBG) = SurfaceMap()
@inline use_only_active_west_cells(::DistributedActiveCellsIBG)  = WestMap()
@inline use_only_active_east_cells(::DistributedActiveCellsIBG)  = EastMap()
@inline use_only_active_south_cells(::DistributedActiveCellsIBG) = SouthMap()
@inline use_only_active_nouth_cells(::DistributedActiveCellsIBG) = NorthMap()

@inline active_cells_work_layout(group, size, ::InteriorMap, grid::ActiveCellsIBG)            = min(length(grid.interior_active_cells), 256), length(grid.interior_active_cells)
@inline active_cells_work_layout(group, size, ::SurfaceMap,  grid::ActiveSurfaceIBG)          = min(length(grid.surface_active_cells),  256), length(grid.surface_active_cells)

@inline active_cells_work_layout(group, size, ::InteriorMap, grid::DistributedActiveCellsIBG) = min(length(grid.interior_active_cells.interior), 256), length(grid.interior_active_cells.interior)
@inline active_cells_work_layout(group, size, ::WestMap,  grid::DistributedActiveCellsIBG) = min(length(grid.interior_active_cells.west),  256), length(grid.interior_active_cells.west)
@inline active_cells_work_layout(group, size, ::EastMap,  grid::DistributedActiveCellsIBG) = min(length(grid.interior_active_cells.east),  256), length(grid.interior_active_cells.east)
@inline active_cells_work_layout(group, size, ::SouthMap, grid::DistributedActiveCellsIBG) = min(length(grid.interior_active_cells.south), 256), length(grid.interior_active_cells.south)
@inline active_cells_work_layout(group, size, ::NorthMap, grid::DistributedActiveCellsIBG) = min(length(grid.interior_active_cells.north), 256), length(grid.interior_active_cells.north)

@inline active_linear_index_to_tuple(idx, ::InteriorMap, grid::ActiveCellsIBG)            = Base.map(Int, grid.interior_active_cells[idx])
@inline active_linear_index_to_tuple(idx, ::InteriorMap, grid::DistributedActiveCellsIBG) = Base.map(Int, grid.interior_active_cells.interior[idx])
@inline active_linear_index_to_tuple(idx, ::WestMap,     grid::DistributedActiveCellsIBG) = Base.map(Int, grid.interior_active_cells.west[idx])
@inline active_linear_index_to_tuple(idx, ::EastMap,     grid::DistributedActiveCellsIBG) = Base.map(Int, grid.interior_active_cells.east[idx])
@inline active_linear_index_to_tuple(idx, ::SouthMap,    grid::DistributedActiveCellsIBG) = Base.map(Int, grid.interior_active_cells.south[idx])
@inline active_linear_index_to_tuple(idx, ::NorthMap,    grid::DistributedActiveCellsIBG) = Base.map(Int, grid.interior_active_cells.north[idx])

@inline  active_linear_index_to_surface_tuple(idx, grid::ActiveSurfaceIBG) = Base.map(Int, grid.surface_active_cells[idx])

function ImmersedBoundaryGrid(grid, ib; active_cells_map::Bool = true) 

    ibg = ImmersedBoundaryGrid(grid, ib)
    TX, TY, TZ = topology(ibg)
    
    # Create the cells map on the CPU, then switch it to the GPU
    if active_cells_map 
        interior_map = active_cells_interior_map(ibg)
        surface_map  = active_cells_surface_map(ibg)
        surface_map  = arch_array(architecture(ibg), surface_map)
    else
        interior_map = nothing
        surface_map  = nothing
    end

    return ImmersedBoundaryGrid{TX, TY, TZ}(ibg.underlying_grid, 
                                            ibg.immersed_boundary, 
                                            interior_map,
                                            surface_map)
end

@inline active_cell(i, j, k, ibg) = !immersed_cell(i, j, k, ibg)
@inline active_column(i, j, k, grid, column) = column[i, j, k] != 0

function compute_interior_active_cells(ibg)
    is_immersed_operation = KernelFunctionOperation{Center, Center, Center}(active_cell, ibg)
    active_cells_field = Field{Center, Center, Center}(ibg, Bool)
    set!(active_cells_field, is_immersed_operation)
    return active_cells_field
end

function compute_surface_active_cells(ibg)
    one_field = ConditionalOperation{Center, Center, Center}(OneField(Int), identity, ibg, NotImmersed(truefunc), 0)
    column    = sum(one_field, dims = 3)
    is_immersed_column = KernelFunctionOperation{Center, Center, Nothing}(active_column, ibg, column)
    active_cells_field = Field{Center, Center, Nothing}(ibg, Bool)
    set!(active_cells_field, is_immersed_column)
    return active_cells_field
end

const MAXUInt8  = 2^8  - 1
const MAXUInt16 = 2^16 - 1
const MAXUInt32 = 2^32 - 1

function active_cells_interior_map(ibg)
    active_cells_field = compute_interior_active_cells(ibg)
    
    N = maximum(size(ibg))
    IntType = N > MAXUInt8 ? (N > MAXUInt16 ? (N > MAXUInt32 ? UInt64 : UInt32) : UInt16) : UInt8
   
    IndicesType = Tuple{IntType, IntType, IntType}

    # Cannot findall on the entire field because we incur on OOM errors
    active_indices = IndicesType[]
    active_indices = findall_active_indices!(active_indices, active_cells_field, ibg, IndicesType)
    active_indices = arch_array(architecture(ibg), active_indices)

    return active_indices
end

# Cannot `findall` on very large grids, so we split the computation in levels.
# This makes the computation a little heavier but avoids OOM errors (this computation
# is performed only once on setup)
function findall_active_indices!(active_indices, active_cells_field, ibg, IndicesType)
    
    for k in 1:size(ibg, 3)
        interior_indices = findall(arch_array(CPU(), interior(active_cells_field, :, :, k:k)))
        interior_indices = convert_interior_indices(interior_indices, k, IndicesType)
        active_indices = vcat(active_indices, interior_indices)
        GC.gc()
    end

    return active_indices
end

function convert_interior_indices(interior_indices, k, IndicesType)
    interior_indices =   getproperty.(interior_indices, :I) 
    interior_indices = add_3rd_index.(interior_indices, k) |> Array{IndicesType}
    return interior_indices
end

@inline add_3rd_index(t::Tuple, k) = (t[1], t[2], k) 

# If we eventually want to perform also barotropic step, `w` computation and `p` 
# computation only on active `columns`
function active_cells_surface_map(ibg)
    active_cells_field = compute_surface_active_cells(ibg)
    interior_cells     = arch_array(CPU(), interior(active_cells_field, :, :, 1))
  
    full_indices = findall(interior_cells)

    Nx, Ny, Nz = size(ibg)
    # Reduce the size of the active_cells_map (originally a tuple of Int64)
    N = max(Nx, Ny)
    IntType = N > MAXUInt8 ? (N > MAXUInt16 ? (N > MAXUInt32 ? UInt64 : UInt32) : UInt16) : UInt8
    smaller_indices = getproperty.(full_indices, Ref(:I)) .|> Tuple{IntType, IntType}
    
    return smaller_indices
end

# In case of a `DistributedGrid` we want to have different maps depending on the 
# partitioning of the domain
function active_cells_interior_map(ibg::ImmersedBoundaryGrid{<:DistributedGrid})
    active_cells_field = compute_interior_active_cells(ibg)
    
    N = maximum(size(ibg))
    IntType = N > MAXUInt8 ? (N > MAXUInt16 ? (N > MAXUInt32 ? UInt64 : UInt32) : UInt16) : UInt8
   
    IndicesType = Tuple{IntType, IntType, IntType}

    # Cannot findall on the entire field because we incur on OOM errors
    active_indices = IndicesType[]
    active_indices = findall_active_indices!(active_indices, active_cells_field, ibg, IndicesType)
    active_indices = separate_active_indices!(active_indices, ibg)

    return active_indices
end

function separate_active_indices!(indices, ibg)
    arch = architecture(ibg)
    Hx, Hy, _ = halo_size(ibg)
    Nx, Ny, _ = size(ibg)
    Rx, Ry, _ = arch.ranks
    west  = Rx > 1 ? findall(idx -> idx[1] <= Hx,    indices) : nothing
    east  = Rx > 1 ? findall(idx -> idx[1] >= Nx-Hx, indices) : nothing
    south = Ry > 1 ? findall(idx -> idx[2] <= Hy,    indices) : nothing
    north = Ry > 1 ? findall(idx -> idx[2] >= Ny-Hy, indices) : nothing

    interior  = findall(idx -> !(idx ∈ west) && !(idx ∈ east) && !(idx ∈ south) && !(idx ∈ north), indices) 

    interior  = arch_array(architecture(ibg), interior)

    west  = west  isa Nothing ? nothing : arch_array(architecture(ibg), west)
    east  = east  isa Nothing ? nothing : arch_array(architecture(ibg), east)
    south = south isa Nothing ? nothing : arch_array(architecture(ibg), south)
    north = north isa Nothing ? nothing : arch_array(architecture(ibg), north)

    return (; interior, west, east, south, north)
end