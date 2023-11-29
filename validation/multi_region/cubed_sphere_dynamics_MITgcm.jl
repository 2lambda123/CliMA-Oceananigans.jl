#=
Download the directory MITgcm_Output from  
https://www.dropbox.com/scl/fo/qr024ly4t3eq38jsi0sdj/h?rlkey=zbq50ud1mtv8l05wxjarulpr3&dl=0
and place it in the path validation/multi_region/. Then run this script from the same path as
include("cubed_sphere_dynamics_MITgcm.jl")
=#

using Oceananigans, Printf

using Oceananigans.BoundaryConditions: fill_halo_regions!
using Oceananigans.Fields: replace_horizontal_vector_halos!
using Oceananigans.Grids: φnode, λnode, halo_size, total_size
using Oceananigans.MultiRegion: getregion, number_of_regions
using Oceananigans.Operators
using Oceananigans.Utils: Iterate
using CairoMakie

include("cubed_sphere_visualization.jl")

g = 9.81

Nx = 32
Ny = 32
Nz = 1

Lz = 1
R  = 6370e3            # sphere's radius
U  = 38.60328935834681 # velocity scale

grid = ConformalCubedSphereGrid(; panel_size = (Nx, Ny, Nz),
                                  z = (-Lz, 0),
                                  radius = R,
                                  horizontal_direction_halo = 2,
                                  partition = CubedSpherePartition(; R = 1))

Hx, Hy, Hz = halo_size(grid)

# Solid body rotation
Ω_prime = U/R
π_MITgcm = 3.14159265358979323844
Ω = 2π_MITgcm/86400

ψᵣ(λ, φ, z) = -R^2*Ω_prime/(2Ω)*2Ω*sind(φ) # ψᵣ(λ, φ, z) = -U * R * sind(φ)

#=
for φʳ = 90; ψᵣ(λ, φ, z) = - U * R * sind(φ)
             uᵣ(λ, φ, z) = - 1 / R * ∂φ(ψᵣ) = U * cosd(φ)
             vᵣ(λ, φ, z) = + 1 / (R * cosd(φ)) * ∂λ(ψᵣ) = 0
             ζᵣ(λ, φ, z) = - 1 / (R * cosd(φ)) * ∂φ(uᵣ * cosd(φ)) = 2 * (U / R) * sind(φ)
=#
ψ = Field{Face, Face, Center}(grid)

# Note that set! fills only interior points; to compute u and v we need information in the halo regions.
set!(ψ, ψᵣ)

#=
Note: fill_halo_regions! works for (Face, Face, Center) field, *except* for the two corner points that do not correspond 
to an interior point! We need to manually fill the Face-Face halo points of the two cornersn that do not have a 
corresponding interior point.
=#

for region in [1, 3, 5]
    i = 1
    j = Ny+1
    for k in 1:Nz
        λ = λnode(i, j, k, grid[region], Face(), Face(), Center())
        φ = φnode(i, j, k, grid[region], Face(), Face(), Center())
        ψ[region][i, j, k] = ψᵣ(λ, φ, 0)
    end
end

for region in [2, 4, 6]
    i = Nx+1
    j = 1
    for k in 1:Nz
        λ = λnode(i, j, k, grid[region], Face(), Face(), Center())
        φ = φnode(i, j, k, grid[region], Face(), Face(), Center())
        ψ[region][i, j, k] = ψᵣ(λ, φ, 0)
    end
end

for passes in 1:3
    fill_halo_regions!(ψ)
end

u = XFaceField(grid)
v = YFaceField(grid)

for region in 1:number_of_regions(grid)
    for j in 1:grid.Ny, i in 1:grid.Nx, k in 1:grid.Nz
        u[region][i, j, k] = - (ψ[region][i, j+1, k] - ψ[region][i, j, k]) / grid[region].Δyᶠᶜᵃ[i, j]
        v[region][i, j, k] =   (ψ[region][i+1, j, k] - ψ[region][i, j, k]) / grid[region].Δxᶜᶠᵃ[i, j]
    end
end

u₀ = deepcopy(u)
v₀ = deepcopy(v)

# Now, compute the vorticity.
using Oceananigans.Utils
using KernelAbstractions: @kernel, @index

ζ = Field{Face, Face, Center}(grid)

@kernel function _compute_vorticity!(ζ, grid, u, v)
    i, j, k = @index(Global, NTuple)
    @inbounds ζ[i, j, k] = ζ₃ᶠᶠᶜ(i, j, k, grid, u, v)
end

offset = -1 .* halo_size(grid)
@apply_regionally begin
    params = KernelParameters(total_size(ζ[1]), offset)
    launch!(CPU(), grid, params, _compute_vorticity!, ζ, grid, u, v)
end

model = HydrostaticFreeSurfaceModel(; grid,
                                    momentum_advection = VectorInvariant(),
                                    free_surface = ExplicitFreeSurface(; gravitational_acceleration = g),
                                    buoyancy = nothing)

# Initial conditions

fac = -(R^2) * Ω_prime * (Ω + 0.5Ω_prime) / (4g * Ω^2)
 
for region in 1:number_of_regions(grid)
    model.velocities.u[region] .= u[region]
    model.velocities.v[region] .= v[region]
    
    for j in 1:grid.Ny, i in 1:grid.Nx, k in grid.Nz+1:grid.Nz+1
        φ = φnode(i, j, k, grid[region], Center(), Center(), Center())
        f = 2 * Ω * sind(φ)
        model.free_surface.η[region][i, j, k] = fac * f^2
    end
end

Δt = 1200
stop_time = 86400 # 1 day
simulation = Simulation(model; Δt, stop_time)

# Print a progress message
progress_message(sim) = @printf("Iteration: %04d, time: %s, Δt: %s, max(|u|): %.2e, wall time: %s\n",
                                iteration(sim), prettytime(sim), prettytime(sim.Δt),
                                maximum(abs, sim.model.velocities.u),
                                prettytime(sim.run_wall_time))

simulation.callbacks[:progress] = Callback(progress_message, IterationInterval(20))

u_fields = Field[]
save_u(sim) = push!(u_fields, deepcopy(sim.model.velocities.u))

v_fields = Field[]
save_v(sim) = push!(v_fields, deepcopy(sim.model.velocities.v))

using Oceananigans.Models.HydrostaticFreeSurfaceModels: fill_velocity_halos!
fill_velocity_halos!(simulation.model.velocities)

ζ = Field{Face, Face, Center}(grid)

ζ_fields = Field[]
Δζ_fields = Field[]

@kernel function _compute_vorticity!(ζ, grid, u, v)
    i, j, k = @index(Global, NTuple)
    @inbounds ζ[i, j, k] = ζ₃ᶠᶠᶜ(i, j, k, grid, u, v)
end

@apply_regionally begin
    params = KernelParameters(total_size(ζ[1]), offset)
    launch!(CPU(), grid, params, _compute_vorticity!, ζ, grid, u, v)
end
ζ₀ = deepcopy(ζ) 

function save_vorticity(sim)
    Hx, Hy, Hz = halo_size(grid)

    fill_velocity_halos!(sim.model.velocities)

    u, v, _ = sim.model.velocities
    
    offset = -1 .* halo_size(grid)
    @apply_regionally begin
        params = KernelParameters(total_size(ζ[1]), offset)
        launch!(CPU(), grid, params, _compute_vorticity!, ζ, grid, u, v)
    end

    push!(ζ_fields, deepcopy(ζ))
    
    Δζ_field = deepcopy(ζ)
    for region in 1:number_of_regions(grid)
        for i in 1:grid.Nx, j in 1:grid.Ny, k in 1:grid.Nz
            Δζ_field[region][i, j, k] -= ζ₀[region][i, j, k]
        end
    end
    
    push!(Δζ_fields, Δζ_field)
end

save_fields_iteration_interval = 3
simulation.callbacks[:save_u] = Callback(save_u, IterationInterval(save_fields_iteration_interval))
simulation.callbacks[:save_v] = Callback(save_v, IterationInterval(save_fields_iteration_interval))
simulation.callbacks[:save_vorticity] = Callback(save_vorticity, IterationInterval(save_fields_iteration_interval))

# run!(simulation)

# Plot the initial velocity field.

fig = panel_wise_visualization_with_halos(grid, u₀)
save("u₀_with_halos.png", fig)

fig = panel_wise_visualization(grid, u₀)
save("u₀.png", fig)

fig = panel_wise_visualization_with_halos(grid, v₀)
save("v₀_with_halos.png", fig)

fig = panel_wise_visualization(grid, v₀)
save("v₀.png", fig)

# Plot the initial vorticity field.

fig = panel_wise_visualization_with_halos(grid, ζ₀)
save("ζ₀_with_halos.png", fig)

fig = panel_wise_visualization(grid, ζ₀)
save("ζ₀.png", fig)

#=
fig = panel_wise_visualization(grid, Δζ_fields[end])
save("Δζ.png", fig)

fig = panel_wise_visualization(grid, ζ₀)
save("ζ₀.png", fig)

start_index = 1
use_symmetric_colorrange = true
animation_time = 10 # seconds
framerate = floor(Int, size(Δζ_fields)[1]/animation_time)

create_panel_wise_visualization_animation(grid, Δζ_fields, start_index, use_symmetric_colorrange, framerate, "Δζ")
=#