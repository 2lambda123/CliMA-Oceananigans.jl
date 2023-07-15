#####
##### Utilities for launching kernels
#####

using Oceananigans.Architectures
using Oceananigans.Grids
using Oceananigans.Grids: AbstractGrid

"""Parameters for kernel launch, containing kernel size (`S`) and kernel offsets (`O`)"""
struct KernelParameters{S, O} end

KernelParameters(size, offsets) = KernelParameters{size, offsets}()

worktuple(::KernelParameters{S}) where S = S
offsets(::KernelParameters{S, O}) where {S, O} = O

worktuple(workspec) = workspec
offsets(workspec)  = nothing

flatten_reduced_dimensions(worksize, dims) = Tuple(i ∈ dims ? 1 : worksize[i] for i = 1:3)

function heuristic_workgroup(Wx, Wy, Wz=nothing)

    workgroup = Wx == 1 && Wy == 1 ?

                    # One-dimensional column models:
                    (1, 1) :

                Wx == 1 ?

                    # Two-dimensional y-z slice models:
                    (1, min(256, Wy)) :

                Wy == 1 ?

                    # Two-dimensional x-z slice models:
                    (min(256, Wx), 1) :

                    # Three-dimensional models
                    (16, 16)

    return workgroup
end

function work_layout(grid, worksize::Tuple; kwargs...)
    workgroup = heuristic_workgroup(worksize...)
    return workgroup, worksize
end

"""
    work_layout(grid, dims; include_right_boundaries=false, location=nothing)

Returns the `workgroup` and `worksize` for launching a kernel over `dims`
on `grid`. The `workgroup` is a tuple specifying the threads per block in each
dimension. The `worksize` specifies the range of the loop in each dimension.

Specifying `include_right_boundaries=true` will ensure the work layout includes the
right face end points along bounded dimensions. This requires the field `location`
to be specified.

For more information, see: https://github.com/CliMA/Oceananigans.jl/pull/308
"""
function work_layout(grid, workdims::Symbol; include_right_boundaries=false, location=nothing, reduced_dimensions=())

    Nx′, Ny′, Nz′ = include_right_boundaries ? size(location, grid) : size(grid)
    Nx′, Ny′, Nz′ = flatten_reduced_dimensions((Nx′, Ny′, Nz′), reduced_dimensions)

    workgroup = heuristic_workgroup(Nx′, Ny′, Nz′)

    # Drop omitted dimemsions
    worksize = workdims == :xyz ? (Nx′, Ny′, Nz′) :
               workdims == :xy  ? (Nx′, Ny′) :
               workdims == :xz  ? (Nx′, Nz′) :
               workdims == :yz  ? (Ny′, Nz′) : throw(ArgumentError("Unsupported launch configuration: $workdims"))

    return workgroup, worksize
end

@inline active_cells_work_layout(workgroup, worksize, only_active_cells, grid) = workgroup, worksize
@inline use_only_active_interior_cells(grid) = nothing

"""
    launch!(arch, grid, layout, kernel!, args...; kwargs...)

Launches `kernel!`, with arguments `args` and keyword arguments `kwargs`,
over the `dims` of `grid` on the architecture `arch`. kernels run on the defaul stream
"""
function launch!(arch, grid, workspec, kernel!, kernel_args...;
                 include_right_boundaries = false,
                 reduced_dimensions = (),
                 location = nothing,
                 only_active_cells = nothing,
                 kwargs...)

    workgroup, worksize = work_layout(grid, worktuple(workspec);
                                      include_right_boundaries,
                                      reduced_dimensions,
                                      location)

    if !only_active_cells
        only_active_cells = nothing
    end
    
    offset = offsets(workspec)

    if !isnothing(only_active_cells) 
        workgroup, worksize = active_cells_work_layout(workgroup, worksize, only_active_cells, grid) 
        offset = nothing
    end

    if worksize == 0
        return nothing
    end
    
    loop! = isnothing(offset) ? kernel!(Architectures.device(arch), workgroup, worksize) : 
                                kernel!(Architectures.device(arch), workgroup, worksize, offset) 

    @info "Launching kernel $kernel! with worksize $worksize and offsets $offset from $workspec"

    loop!(kernel_args...)

    return nothing
end

# When dims::Val
@inline launch!(arch, grid, ::Val{workspec}, args...; kwargs...) where workspec =
    launch!(arch, grid, workspec, args...; kwargs...)
