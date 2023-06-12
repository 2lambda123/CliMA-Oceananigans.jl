import Oceananigans.Distributed: compute_boundary_tendencies!
using Oceananigans.Utils: worktuple, offsets
using Oceananigans.TurbulenceClosures: required_halo_size

# We assume here that top/bottom BC are always synched (no partitioning in z)
function compute_boundary_tendencies!(model::HydrostaticFreeSurfaceModel)
    grid = model.grid
    arch = architecture(grid)

    # We need new values for `w`, `p` and `κ`
    recompute_auxiliaries!(model, grid, arch)

    # parameters for communicating North / South / East / West side
    kernel_parameters = boundary_tendency_kernel_parameters(grid, arch)
    calculate_hydrostatic_free_surface_tendency_contributions!(model, kernel_parameters)

    return nothing
end

# tendencies need computing in the range 1 : H and N - H + 1 : N 
function boundary_tendency_kernel_parameters(grid, arch)
    Nx, Ny, Nz = size(grid)
    Hx, Hy, _  = halo_size(grid)
    
    Sx  = (Hx, Ny, Nz)
    Sy  = (Nx, Hy, Nz)
         
    Oᴸ  = (0,  0,  0)
    Oᴿx = (Nx-Hx, 0,     0)
    Oᴿy = (0,     Ny-Hy, 0)

    sizes = (Sx, Sy,  Sx,  Sy)
    offs  = (Oᴸ, Oᴸ, Oᴿx, Oᴿy)
        
    return boundary_parameters(sizes, offs, grid, arch)
end

function recompute_auxiliaries!(model, grid, arch)
    
    w_kernel_parameters = boundary_w_kernel_parameters(grid, arch)
    p_kernel_parameters = boundary_p_kernel_parameters(grid, arch)
    κ_kernel_parameters = boundary_κ_kernel_parameters(grid, model.closure, arch)

    for (wpar, ppar, κpar) in zip(w_kernel_parameters, p_kernel_parameters, κ_kernel_parameters)
        compute_w_from_continuity!(model.velocities, arch, grid; parameters = wpar)
        update_hydrostatic_pressure!(model.pressure.pHY′, arch, grid, model.buoyancy, model.tracers; parameters = ppar)
        calculate_diffusivities!(model.diffusivity_fields, model.closure, model; parameters = κpar)
    end
end

# w needs computing in the range - H + 1 : 0 and N - 1 : N + H - 1
function boundary_w_kernel_parameters(grid, arch)
    Nx, Ny, _ = size(grid)
    Hx, Hy, _ = halo_size(grid)

    Sx  = (Hx, Ny)
    Sy  = (Nx, Hy)
             
    Oᴸx = (-Hx+1, 0)
    Oᴸy = (0, -Hy+1)
    Oᴿx = (Nx-1,  0)
    Oᴿy = (0,  Ny-1)

    sizes = ( Sx,  Sy,  Sx,  Sy)
    offs  = (Oᴸx, Oᴸy, Oᴿx, Oᴿy)
        
    return boundary_parameters(sizes, offs, grid, arch)
end

# p needs computing in the range  0 : 0 and N + 1 : N + 1
function boundary_p_kernel_parameters(grid, arch)
    Nx, Ny, _ = size(grid)

    Sx  = (1, Ny)
    Sy  = (Nx, 1)
             
    Oᴸx = (-1, 0)
    Oᴸy = (0, -1)
    Oᴿx = (Nx, 0)
    Oᴿy = (0, Ny)

    sizes = ( Sx,  Sy,  Sx,  Sy)
    offs  = (Oᴸx, Oᴸy, Oᴿx, Oᴿy)
        
    return boundary_parameters(sizes, offs, grid, arch)
end

# diffusivities need computing in the range 0 : B and N - B : N + 1
function boundary_κ_kernel_parameters(grid, closure, arch)
    Nx, Ny, Nz = size(grid)

    B = required_halo_size(closure)

    Sx  = (B+1, Ny, Nz)
    Sy  = (Nx, B+1, Nz)
        
    Oᴸx = (-1, 0, 0)
    Oᴸy = (0, -1, 0)
    Oᴿx = (Nx-B,  0, 0)
    Oᴿy = (0,  Ny-B, 0)

    sizes = ( Sx,  Sy,  Sx,  Sy)
    offs  = (Oᴸx, Oᴸy, Oᴿx, Oᴿy)
        
    return boundary_parameters(sizes, offs, grid, arch)
end

using Oceananigans.Operators: XFlatGrid, YFlatGrid

# Recompute only on communicating sides 
function boundary_parameters(S, O, grid, arch) 
    Rx, Ry, _ = arch.ranks

    include_x = !isa(grid, XFlatGrid) && (Rx != 1)
    include_y = !isa(grid, YFlatGrid) && (Ry != 1)

    if include_x && include_y
        return tuple(KernelParameters(S[i], O[i]) for i in 1:4)
    elseif include_x && !(include_y)
        return tuple(KernelParameters(S[i], O[i]) for i in 1:2:3)
    elseif !(include_x) && include_y
        return tuple(KernelParameters(S[i], O[i]) for i in 2:2:4)
    else
        return ()
    end
end

