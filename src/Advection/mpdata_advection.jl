using Oceananigans.BoundaryConditions
using Oceananigans.Fields
using Oceananigans.Fields: VelocityFields, location
using KernelAbstractions: @kernel, @index
using Oceananigans.Utils
using Adapt 

struct MPData{FT, I, A, V} <: AbstractUpwindBiasedAdvectionScheme{1, FT} 
    velocities :: A
    previous_velocities :: A
    vertical_advection :: V
    iterations :: I
    MPData{FT}(v::A, pv::A, va::V, i::I) where {FT, A, V, I} = new{FT, I, A, V}(v, pv, va, i)
end

function MPData(grid; iterations = nothing,
                      vertical_advection = nothing)
    velocities = VelocityFields(grid)
    previous_velocities = VelocityFields(grid)
    return MPData{eltype(grid)}(velocities, previous_velocities, vertical_advection, iterations)
end

Adapt.adapt_structure(to, scheme::MPData{FT}) where FT = 
    MPData{FT}(Adapt.adapt(to, scheme.velocities),
               Adapt.adapt(to, scheme.previous_velocities),
               Adapt.adapt(to, scheme.vertical_advection),
               Adapt.adapt(to, scheme.iterations))

# Optimal MPData scheme from "Antidiffusive Velocities for Multipass Donor Cell Advection"
# which has only two passes 
const OptimalMPData = MPData{<:Any, <:Nothing}

# Different scheme in the vertical direction
const PartialMPData = MPData{<:Any, <:Any, <:AbstractAdvectionScheme}

# Basically just first order upwind (also called the "donor cell" scheme)
@inline symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, ::MPData, c, args...) = ℑxᶠᵃᵃ(i, j, k, grid, c, args...)
@inline symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, ::MPData, c, args...) = ℑyᵃᶠᵃ(i, j, k, grid, c, args...)
@inline symmetric_interpolate_zᵃᵃᶠ(i, j, k, grid, ::MPData, c, args...) = ℑzᵃᵃᶠ(i, j, k, grid, c, args...)

@inline symmetric_interpolate_xᶜᵃᵃ(i, j, k, grid, ::MPData, u, args...) = ℑxᶜᵃᵃ(i, j, k, grid, u, args...)
@inline symmetric_interpolate_yᵃᶜᵃ(i, j, k, grid, ::MPData, v, args...) = ℑyᵃᶜᵃ(i, j, k, grid, v, args...)
@inline symmetric_interpolate_zᵃᵃᶜ(i, j, k, grid, ::MPData, w, args...) = ℑzᵃᵃᶜ(i, j, k, grid, w, args...)

@inline inner_left_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, ::MPData, ψ, idx, loc, args...) = @inbounds ψ[i-1, j, k]
@inline inner_left_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, ::MPData, ψ, idx, loc, args...) = @inbounds ψ[i, j-1, k]
@inline inner_left_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, ::MPData, ψ, idx, loc, args...) = @inbounds ψ[i, j, k-1]

@inline inner_right_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, ::MPData, ψ, idx, loc, args...) = @inbounds ψ[i, j, k]
@inline inner_right_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, ::MPData, ψ, idx, loc, args...) = @inbounds ψ[i, j, k]
@inline inner_right_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, ::MPData, ψ, idx, loc, args...) = @inbounds ψ[i, j, k]

@inline inner_left_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, ::MPData, ψ::Function, idx, loc, args...) = @inbounds ψ(i-1, j, k, grid, args...)
@inline inner_left_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, ::MPData, ψ::Function, idx, loc, args...) = @inbounds ψ(i, j-1, k, grid, args...)
@inline inner_left_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, ::MPData, ψ::Function, idx, loc, args...) = @inbounds ψ(i, j, k-1, grid, args...)

@inline inner_right_biased_interpolate_xᶠᵃᵃ(i, j, k, grid, ::MPData, ψ::Function, idx, loc, args...) = @inbounds ψ(i, j, k, grid, args...)
@inline inner_right_biased_interpolate_yᵃᶠᵃ(i, j, k, grid, ::MPData, ψ::Function, idx, loc, args...) = @inbounds ψ(i, j, k, grid, args...)
@inline inner_right_biased_interpolate_zᵃᵃᶠ(i, j, k, grid, ::MPData, ψ::Function, idx, loc, args...) = @inbounds ψ(i, j, k, grid, args...)

function correct_advection!(model, Δt)
    grid = model.grid
    velocities = model.velocities
    
    for tracer_name in propertynames(model.tracers)
        @inbounds tracer = model.tracers[tracer_name]
        @inbounds scheme = model.advection[tracer_name]
        correct_mpdata_tracer!(tracer, grid, Δt, velocities, scheme)
    end

    correct_mpdata_momentum!(velocities, grid, Δt, model.advection)

    return nothing
end

correct_mpdata_momentum!(velocities, grid, Δt, scheme) = nothing

function correct_mpdata_momentum!(velocities, grid, Δt, scheme::MPData)
    pseudo_velocities = scheme.velocities
    previous_velocities = scheme.previous_velocities

    set!(pseudo_velocities.u, velocities.u)
    set!(pseudo_velocities.v, velocities.v)
    set!(pseudo_velocities.w, velocities.w)

    set!(previous_velocities.u, velocities.u)
    set!(previous_velocities.v, velocities.v)
    set!(previous_velocities.w, velocities.w)

    mpdata_iterate!(velocities.u, grid, scheme, pseudo_velocities, Δt, div_𝐯u)

    set!(pseudo_velocities.u, previous_velocities.u)
    set!(pseudo_velocities.v, previous_velocities.v)
    set!(pseudo_velocities.w, previous_velocities.w)

    mpdata_iterate!(velocities.v, grid, scheme, pseudo_velocities, Δt, div_𝐯u)

    return nothing
end

correct_mpdata_tracer!(field, grid, Δt, velocities, scheme) = nothing 

function correct_mpdata_tracer!(field, grid, Δt, velocities, scheme::MPData) 
    pseudo_velocities = scheme.velocities

    set!(pseudo_velocities.u, velocities.u)
    set!(pseudo_velocities.v, velocities.v)
    set!(pseudo_velocities.w, velocities.w)

    mpdata_iterate!(field, grid, scheme, pseudo_velocities, Δt, div_Uc)

    return nothing
end

function mpdata_iterate!(field, grid, scheme::OptimalMPData, pseudo_velocities, Δt, divUc)

    fill_halo_regions!(field)
    launch!(architecture(grid), grid, :xyz, _calculate_optimal_mpdata_velocities!, 
            pseudo_velocities, grid, field, Δt)

    fill_halo_regions!(pseudo_velocities)
    launch!(architecture(grid), grid, :xyz, _update_tracer!, field, 
            scheme, pseudo_velocities, grid, divUc, Δt) 

    return nothing
end

function mpdata_iterate!(field, grid, scheme, pseudo_velocities, Δt, divUc)

    for iter in 1:scheme.iterations
        fill_halo_regions!(field)
        launch!(architecture(grid), grid, :xyz, _calculate_mpdata_velocities!, 
                pseudo_velocities, grid, field, Δt)

        fill_halo_regions!(pseudo_velocities)
        launch!(architecture(grid), grid, :xyz, _update_tracer!, field, scheme, 
                pseudo_velocities, grid, divUc, Δt) 
    end

    return nothing
end

""" 
Pseudo-velocities are calculated as:

uᵖ = abs(u)(1 - abs(u)) A - u v B - u w C
vᵖ = abs(v)(1 - abs(v)) B - u v A - v w C
wᵖ = abs(w)(1 - abs(w)) C - u w A - v w B

where A = Δx / 2ψ ∂x(ψ)
and   B = Δy / 2ψ ∂y(ψ)
and   C = Δz / 2ψ ∂z(ψ)
"""
@kernel function _calculate_mpdata_velocities!(velocities, grid, ψ, Δt)
    i, j, k = @index(Global, NTuple)

    Aᶠᶜᶜ, Bᶠᶜᶜ, Cᶠᶜᶜ, Aᶜᶠᶜ, Bᶜᶠᶜ, Cᶜᶠᶜ, Aᶜᶜᶠ, Bᶜᶜᶠ, Cᶜᶜᶠ = mpdata_auxiliaries(i, j, k, grid, ψ)
    uᵖ, vᵖ, wᵖ = velocities

    ξ, η, ζ = mpdata_pseudo_velocities(i, j, k, grid, Δt, velocities, Aᶠᶜᶜ, Bᶠᶜᶜ, Cᶠᶜᶜ, Aᶜᶠᶜ, Bᶜᶠᶜ, Cᶜᶠᶜ, Aᶜᶜᶠ, Bᶜᶜᶠ, Cᶜᶜᶠ)

    @inbounds begin
        uᵖ[i, j, k] = min(abs(uᵖ[i, j, k]), abs(ξ)) * sign(ξ)
        vᵖ[i, j, k] = min(abs(vᵖ[i, j, k]), abs(η)) * sign(η)
        wᵖ[i, j, k] = min(abs(wᵖ[i, j, k]), abs(ζ)) * sign(ζ)
    end 
end

""" 
Pseudo-velocities are calculated as:

uᵖ = ∑₁∞ abs(uᴾ)(1 - abs(uᴾ)) A - uᴾ vᴾ B - uᵖ wᵖ C
vᵖ = ∑₁∞ abs(vᴾ)(1 - abs(vᴾ)) B - uᴾ vᴾ A - vᵖ wᵖ C
wᵖ = ∑₁∞ abs(wᴾ)(1 - abs(wᴾ)) C - uᴾ wᴾ A - vᵖ wᵖ B

where A = Δx / 2ψ ∂x(ψ) stays fixed
and   B = Δy / 2ψ ∂y(ψ) stays fixed
"""
@kernel function _calculate_optimal_mpdata_velocities!(velocities, grid, ψ, Δt)
    i, j, k = @index(Global, NTuple)

    uᵖ, vᵖ, wᵖ = velocities
    Aᶠᶜᶜ, Bᶠᶜᶜ, Cᶠᶜᶜ, Aᶜᶠᶜ, Bᶜᶠᶜ, Cᶜᶠᶜ, Aᶜᶜᶠ, Bᶜᶜᶠ, Cᶜᶜᶠ = mpdata_auxiliaries(i, j, k, grid, ψ)

    @inbounds begin
        u_abs = abs(uᵖ[i, j, k])
        v_abs = abs(vᵖ[i, j, k])
        
        Aₐᶠᶜᶜ = abs(Aᶠᶜᶜ)
        Bₐᶠᶜᶜ = abs(Bᶠᶜᶜ)
        Aₐᶜᶠᶜ = abs(Aᶜᶠᶜ)
        Bₐᶜᶠᶜ = abs(Bᶜᶠᶜ)

        ξ, η, ζ = mpdata_pseudo_velocities(i, j, k, grid, Δt, velocities, Aᶠᶜᶜ, Bᶠᶜᶜ, Cᶠᶜᶜ, Aᶜᶠᶜ, Bᶜᶠᶜ, Cᶜᶠᶜ, Aᶜᶜᶠ, Bᶜᶜᶠ, Cᶜᶜᶠ)

        ξ *= Δt / Δxᶠᶜᶜ(i, j, k, grid)
        η *= Δt / Δyᶜᶠᶜ(i, j, k, grid)  
        ξ *= Δt / Δzᶜᶜᶠ(i, j, k, grid)

        dˣ₁ = (1 - Aₐᶠᶜᶜ)
        dˣ₂ = (1 - Aₐᶠᶜᶜ^2)
        dˣ₃ = (1 - Aₐᶠᶜᶜ^3)

        cΣᵅ = abs(dˣ₁) > 0
        cΣᵝ = cΣᵅ & (abs(dˣ₂) > 0)
        cΣᵞ = cΣᵝ & (abs(dˣ₃) > 0)
        Σˣᵅ = ifelse(cΣᵅ, 1 / dˣ₁,                         0)
        Σˣᵝ = ifelse(cΣᵝ, - Aᶠᶜᶜ / (dˣ₁ * dˣ₂),            0)
        Σˣᵞ = ifelse(cΣᵞ, 2 * Aₐᶠᶜᶜ^3 / (dˣ₁ * dˣ₂ * dˣ₃), 0)

        dʸ₁ = (1 - Bₐᶜᶠᶜ)
        dʸ₂ = (1 - Bₐᶜᶠᶜ^2)
        dʸ₃ = (1 - Bₐᶜᶠᶜ^3)

        cΣᵅ = abs(dʸ₁) > 0
        cΣᵝ = cΣᵅ & (abs(dʸ₂) > 0)
        cΣᵞ = cΣᵝ & (abs(dʸ₃) > 0)
        Σʸᵅ = ifelse(cΣᵅ, 1 / dʸ₁,                         0)
        Σʸᵝ = ifelse(cΣᵝ, - Bᶜᶠᶜ / (dʸ₁ * dʸ₂),            0)
        Σʸᵞ = ifelse(cΣᵞ, 2 * Bₐᶜᶠᶜ^3 / (dʸ₁ * dʸ₂ * dʸ₃), 0)

        dᶻ₁ = (1 - Cₐᶜᶜᶠ)
        dᶻ₂ = (1 - Cₐᶜᶜᶠ^2)
        dᶻ₃ = (1 - Cₐᶜᶜᶠ^3)

        cΣᵅ = abs(dᶻ₁) > 0
        cΣᵝ = cΣᵅ & (abs(dᶻ₂) > 0)
        cΣᵞ = cΣᵝ & (abs(dᶻ₃) > 0)
        Σᶻᵅ = ifelse(cΣᵅ, 1 / dᶻ₁,                         0)
        Σᶻᵝ = ifelse(cΣᵝ, - Cᶜᶜᶠ / (dᶻ₁ * dᶻ₂),            0)
        Σᶻᵞ = ifelse(cΣᵞ, 2 * Cₐᶜᶜᶠ^3 / (dᶻ₁ * dᶻ₂ * dᶻ₃), 0)

        dˣʸ₁ = (1 - abs(Aᶠᶜᶜ   * Bᶠᶜᶜ))
        dˣʸ₂ = (1 - abs(Aᶠᶜᶜ^2 * Bᶠᶜᶜ))
        dˣʸ₃ = (1 - abs(Aᶠᶜᶜ   * Bᶠᶜᶜ^2))

        cΣᵃ  = (abs(dˣ₁) > 0) & (abs(dˣʸ₁) > 1)
        cΣᵇ  = cΣᵃ & (abs(dˣʸ₂) > 0) & (abs(dˣ₂) > 0)
        cΣᶜ  = cΣᵃ & (abs(dˣʸ₃) > 0) 
        Σˣʸᵃ = ifelse(cΣᵃ, - Bᶠᶜᶜ / (dˣ₁ * dˣʸ₁), 0)
        Σˣʸᵇ = ifelse(cΣᵇ, Bᶠᶜᶜ * Aᶠᶜᶜ / (dˣ₁ * dˣʸ₂) * (Bₐᶠᶜᶜ / dˣʸ₁ + 2Aᶠᶜᶜ / dˣ₂), 0)
        Σˣʸᶜ = ifelse(cΣᶜ, Aₐᶠᶜᶜ * Bᶠᶜᶜ^2 / (dˣ₁ * dˣʸ₃ * dˣʸ₁), 0)

        dʸˣ₁ = (1 - abs(Bᶜᶠᶜ   * Aᶜᶠᶜ))
        dʸˣ₂ = (1 - abs(Bᶜᶠᶜ^2 * Aᶜᶠᶜ))
        dʸˣ₃ = (1 - abs(Bᶜᶠᶜ   * Aᶜᶠᶜ^2))

        cΣᵃ  = (abs(dʸ₁) > 0) & (abs(dʸˣ₁) > 1)
        cΣᵇ  = cΣᵃ & (abs(dʸˣ₂) > 0) & (abs(dʸ₂) > 0)
        cΣᶜ  = cΣᵃ & (abs(dʸˣ₃) > 0) 
        Σʸˣᵃ = ifelse(cΣᵃ, - Aᶜᶠᶜ / (dʸ₁ * dʸˣ₁), 0)
        Σʸˣᵇ = ifelse(cΣᵇ, Aᶜᶠᶜ * Bᶜᶠᶜ / (dʸ₁ * dʸˣ₂) * (Aₐᶜᶠᶜ / dʸˣ₁ + 2Bᶜᶠᶜ / dʸ₂), 0)
        Σʸˣᶜ = ifelse(cΣᶜ, Bₐᶜᶠᶜ * Aᶜᶠᶜ^2 / (dʸ₁ * dʸˣ₃ * dʸˣ₁), 0)

        dˣᶻ₁ = (1 - abs(Aᶠᶜᶜ   * Cᶠᶜᶜ))
        dˣᶻ₂ = (1 - abs(Aᶠᶜᶜ^2 * Cᶠᶜᶜ))
        dˣᶻ₃ = (1 - abs(Aᶠᶜᶜ   * Cᶠᶜᶜ^2))

        cΣᵃ  = (abs(dˣ₁) > 0) & (abs(dˣᶻ₁) > 1)
        cΣᵇ  = cΣᵃ & (abs(dˣᶻ₂) > 0) & (abs(dˣ₂) > 0)
        cΣᶜ  = cΣᵃ & (abs(dˣᶻ₃) > 0) 
        Σˣᶻᵃ = ifelse(cΣᵃ, - Cᶠᶜᶜ / (dˣ₁ * dˣᶻ₁), 0)
        Σˣᶻᵇ = ifelse(cΣᵇ, Cᶠᶜᶜ * Aᶠᶜᶜ / (dˣ₁ * dˣᶻ₂) * (Cₐᶠᶜᶜ / dˣᶻ₁ + 2Aᶠᶜᶜ / dˣ₂), 0)
        Σˣᶻᶜ = ifelse(cΣᶜ, Aₐᶠᶜᶜ * Cᶠᶜᶜ^2 / (dˣ₁ * dˣᶻ₃ * dˣᶻ₁), 0)

        dʸᶻ₁ = (1 - abs(Bᶜᶠᶜ   * Cᶜᶠᶜ))
        dʸᶻ₂ = (1 - abs(Bᶜᶠᶜ^2 * Cᶜᶠᶜ))
        dʸᶻ₃ = (1 - abs(Bᶜᶠᶜ   * Cᶜᶠᶜ^2))

        cΣᵃ  = (abs(dʸ₁) > 0) & (abs(dʸᶻ₁) > 1)
        cΣᵇ  = cΣᵃ & (abs(dʸᶻ₂) > 0) & (abs(dʸ₂) > 0)
        cΣᶜ  = cΣᵃ & (abs(dʸᶻ₃) > 0) 
        Σʸᶻᵃ = ifelse(cΣᵃ, - Cᶜᶠᶜ / (dʸ₁ * dʸᶻ₁), 0)
        Σʸᶻᵇ = ifelse(cΣᵇ, Cᶜᶠᶜ * Bᶜᶠᶜ / (dʸ₁ * dʸᶻ₂) * (Cₐᶜᶠᶜ / dʸᶻ₁ + 2Bᶜᶠᶜ / dʸ₂), 0)
        Σʸᶻᶜ = ifelse(cΣᶜ, Bₐᶜᶠᶜ * Cᶜᶠᶜ^2 / (dʸ₁ * dʸᶻ₃ * dʸᶻ₁), 0)

        dᶻˣ₁ = (1 - abs(Cᶜᶜᶠ   * Aᶜᶜᶠ))
        dᶻˣ₂ = (1 - abs(Cᶜᶜᶠ^2 * Aᶜᶜᶠ))
        dᶻˣ₃ = (1 - abs(Cᶜᶜᶠ   * Aᶜᶜᶠ^2))

        cΣᵃ  = (abs(dᶻ₁) > 0) & (abs(dᶻˣ₁) > 1)
        cΣᵇ  = cΣᵃ & (abs(dᶻˣ₂) > 0) & (abs(dᶻ₂) > 0)
        cΣᶜ  = cΣᵃ & (abs(dᶻˣ₃) > 0) 
        Σᶻˣᵃ = ifelse(cΣᵃ, - Aᶜᶜᶠ / (dᶻ₁ * dᶻˣ₁), 0)
        Σᶻˣᵇ = ifelse(cΣᵇ, Aᶜᶜᶠ * Cᶜᶜᶠ / (dᶻ₁ * dᶻˣ₂) * (Aₐᶜᶜᶠ / dᶻˣ₁ + 2Cᶜᶜᶠ / dᶻ₂), 0)
        Σᶻˣᶜ = ifelse(cΣᶜ, Cₐᶜᶜᶠ * Aᶜᶜᶠ^2 / (dᶻ₁ * dᶻˣ₃ * dᶻˣ₁), 0)

        dᶻʸ₁ = (1 - abs(Cᶜᶜᶠ   * Bᶜᶜᶠ))
        dᶻʸ₂ = (1 - abs(Cᶜᶜᶠ^2 * Bᶜᶜᶠ))
        dᶻʸ₃ = (1 - abs(Cᶜᶜᶠ   * Bᶜᶜᶠ^2))

        cΣᵃ  = (abs(dᶻ₁) > 0) & (abs(dᶻʸ₁) > 1)
        cΣᵇ  = cΣᵃ & (abs(dᶻʸ₂) > 0) & (abs(dᶻ₂) > 0)
        cΣᶜ  = cΣᵃ & (abs(dᶻʸ₃) > 0) 
        Σᶻʸᵃ = ifelse(cΣᵃ, - Bᶜᶜᶠ / (dᶻ₁ * dᶻʸ₁), 0)
        Σᶻʸᵇ = ifelse(cΣᵇ, Bᶜᶜᶠ * Cᶜᶜᶠ / (dᶻ₁ * dᶻʸ₂) * (Bₐᶜᶜᶠ / dᶻʸ₁ + 2Cᶜᶜᶠ / dᶻ₂), 0)
        Σᶻʸᶜ = ifelse(cΣᶜ, Cₐᶜᶜᶠ * Bᶜᶜᶠ^2 / (dᶻ₁ * dᶻʸ₃ * dᶻʸ₁), 0)

        uᵖ[i, j, k] = (Σˣᵅ * ξ + Σˣᵝ * ξ^2 + Σˣᵞ * ξ^3 + 
                       Σˣʸᵃ * ξ * η + Σˣʸᵇ * ξ^2 * η + Σˣʸᶜ * ξ * η^2 +
                       Σˣᶻᵃ * ξ * ζ + Σˣᶻᵇ * ξ^2 * ζ + Σˣᶻᶜ * ξ * ζ^2) * Δxᶠᶜᶜ(i, j, k, grid) / Δt
        vᵖ[i, j, k] = (Σʸᵅ * η + Σʸᵝ * η^2 + Σʸᵞ * η^3 + 
                       Σʸˣᵃ * η * ξ + Σʸˣᵇ * η^2 * ξ + Σʸˣᶜ * η * ξ^2 +
                       Σʸᶻᵃ * η * ζ + Σʸᶻᵇ * η^2 * ζ + Σʸᶻᶜ * η * ζ^2) * Δyᶜᶠᶜ(i, j, k, grid) / Δt
        wᵖ[i, j, k] = (Σᶻᵅ * η + Σᶻᵝ * η^2 + Σᶻᵞ * η^3 + 
                       Σᶻˣᵃ * ζ * ξ + Σᶻˣᵇ * ζ^2 * ξ + Σᶻˣᶜ * ζ * ξ^2 +
                       Σᶻʸᵃ * ζ * η + Σᶻʸᵇ * ζ^2 * η + Σᶻʸᶜ * ζ * η^2) * Δzᶜᶜᶠ(i, j, k, grid) / Δt
        
        
        uᵖ[i, j, k] = min(u_abs, abs(uᵖ[i, j, k])) * sign(uᵖ[i, j, k])
        vᵖ[i, j, k] = min(v_abs, abs(vᵖ[i, j, k])) * sign(vᵖ[i, j, k])
        wᵖ[i, j, k] = min(w_abs, abs(wᵖ[i, j, k])) * sign(wᵖ[i, j, k])
    end 
end

@inline abs_ψ(i, j, k, grid, ψ) = abs(ψ[i, j, k])

@inline function mpdata_auxiliaries(i, j, k, grid, ψ)

    ψ₁ᶠᶜᶜ = 2 * ℑxᶠᵃᵃ(i, j, k, grid, abs_ψ, ψ)
    ψ₁ᶜᶠᶜ = 2 * ℑyᵃᶠᵃ(i, j, k, grid, abs_ψ, ψ)
    ψ₁ᶜᶜᶠ = 2 * ℑzᵃᵃᶠ(i, j, k, grid, abs_ψ, ψ)
    Δψ₁ᶠᶜᶜ = δxᶠᵃᵃ(i, j, k, grid, abs_ψ, ψ)
    Δψ₁ᶜᶠᶜ = δyᵃᶠᵃ(i, j, k, grid, abs_ψ, ψ)
    Δψ₁ᶜᶜᶠ = δzᵃᵃᶠ(i, j, k, grid, abs_ψ, ψ)

    # Calculating A and B
    @inbounds begin
        ψ₂ᶠᶜᶜ = (abs(ψ[i, j+1, k]) + abs(ψ[i-1, j+1, k]) + abs(ψ[i, j-1, k]) + abs(ψ[i-1, j-1, k]))
        ψ₂ᶜᶠᶜ = (abs(ψ[i+1, j, k]) + abs(ψ[i+1, j-1, k]) + abs(ψ[i-1, j, k]) + abs(ψ[i-1, j-1, k]))
        ψ₂ᶜᶜᶠ = (abs(ψ[i, j, k+1]) + abs(ψ[i-1, j, k+1]) + abs(ψ[i, j, k-1]) + abs(ψ[i-1, j, k-1]))

        Δψ₂ᶠᶜᶜ = (abs(ψ[i, j+1, k]) + abs(ψ[i-1, j+1, k]) - abs(ψ[i, j-1, k]) - abs(ψ[i-1, j-1, k]))
        Δψ₂ᶜᶠᶜ = (abs(ψ[i+1, j, k]) + abs(ψ[i+1, j-1, k]) - abs(ψ[i-1, j, k]) - abs(ψ[i-1, j-1, k]))
        Δψ₂ᶜᶜᶠ = (abs(ψ[i, j, k+1]) + abs(ψ[i-1, j, k+1]) - abs(ψ[i, j, k-1]) - abs(ψ[i-1, j, k-1]))

        ψ₃ᶠᶜᶜ = (abs(ψ[i+1, j, k]) + abs(ψ[i+1, j, k-1]) + abs(ψ[i-1, j, k]) + abs(ψ[i-1, j, k-1]))
        ψ₃ᶜᶠᶜ = (abs(ψ[i, j+1, k]) + abs(ψ[i, j+1, k-1]) + abs(ψ[i, j-1, k]) + abs(ψ[i, j-1, k-1]))
        ψ₃ᶜᶜᶠ = (abs(ψ[i, j, k+1]) + abs(ψ[i, j-1, k+1]) + abs(ψ[i, j, k-1]) + abs(ψ[i, j-1, k-1]))

        Δψ₃ᶠᶜᶜ = (abs(ψ[i+1, j, k]) + abs(ψ[i+1, j, k-1]) - abs(ψ[i-1, j, k]) - abs(ψ[i-1, j, k-1]))
        Δψ₃ᶜᶠᶜ = (abs(ψ[i, j+1, k]) + abs(ψ[i, j+1, k-1]) - abs(ψ[i, j-1, k]) - abs(ψ[i, j-1, k-1]))
        Δψ₃ᶜᶜᶠ = (abs(ψ[i, j, k+1]) + abs(ψ[i, j-1, k+1]) - abs(ψ[i, j, k-1]) - abs(ψ[i, j-1, k-1]))

        Aᶠᶜᶜ = ifelse(abs(ψ₁ᶠᶜᶜ) > 0, Δψ₁ᶠᶜᶜ / ψ₁ᶠᶜᶜ, 0)
        Bᶠᶜᶜ = ifelse(abs(ψ₂ᶠᶜᶜ) > 0, Δψ₂ᶠᶜᶜ / ψ₂ᶠᶜᶜ, 0)
        Cᶠᶜᶜ = ifelse(abs(ψ₃ᶠᶜᶜ) > 0, Δψ₃ᶠᶜᶜ / ψ₃ᶠᶜᶜ, 0)

        Aᶜᶠᶜ = ifelse(abs(ψ₂ᶜᶠᶜ) > 0, Δψ₂ᶜᶠᶜ / ψ₂ᶜᶠᶜ, 0)
        Bᶜᶠᶜ = ifelse(abs(ψ₁ᶜᶠᶜ) > 0, Δψ₁ᶜᶠᶜ / ψ₁ᶜᶠᶜ, 0)
        Cᶜᶠᶜ = ifelse(abs(ψ₃ᶜᶠᶜ) > 0, Δψ₃ᶜᶠᶜ / ψ₃ᶜᶠᶜ, 0)

        Aᶜᶜᶠ = ifelse(abs(ψ₂ᶜᶜᶠ) > 0, Δψ₂ᶜᶜᶠ / ψ₂ᶜᶜᶠ, 0)
        Bᶜᶜᶠ = ifelse(abs(ψ₃ᶜᶜᶠ) > 0, Δψ₃ᶜᶜᶠ / ψ₃ᶜᶜᶠ, 0)
        Cᶜᶜᶠ = ifelse(abs(ψ₁ᶜᶜᶠ) > 0, Δψ₁ᶜᶜᶠ / ψ₁ᶜᶜᶠ, 0)        
    end

    return Aᶠᶜᶜ, Bᶠᶜᶜ, Cᶠᶜᶜ, Aᶜᶠᶜ, Bᶜᶠᶜ, Cᶜᶠᶜ, Aᶜᶜᶠ, Bᶜᶜᶠ, Cᶜᶜᶠ
end

@inline function mpdata_pseudo_velocities(i, j, k, grid, Δt, U, Aᶠᶜᶜ, Bᶠᶜᶜ, Cᶠᶜᶜ, Aᶜᶠᶜ, Bᶜᶠᶜ, Cᶜᶠᶜ, Aᶜᶜᶠ, Bᶜᶜᶠ, Cᶜᶜᶠ)

    uᵖ, vᵖ, wᵖ = U

    u_abs = abs(uᵖ[i, j, k])
    v_abs = abs(vᵖ[i, j, k])
    w_abs = abs(wᵖ[i, j, k])

    u̅ᶠᶜᶜ = abs(uᵖ[i, j, k]) * Δt / Δxᶠᶜᶜ(i, j, k, grid)
    v̅ᶜᶠᶜ = abs(vᵖ[i, j, k]) * Δt / Δyᶜᶠᶜ(i, j, k, grid)  
    w̅ᶜᶜᶠ = abs(wᵖ[i, j, k]) * Δt / Δzᶜᶜᶠ(i, j, k, grid) 

    u̅ᶜᶠᶜ = ℑxyᶜᶠᵃ(i, j, k, grid, uᵖ) * Δt / Δxᶜᶠᶜ(i, j, k, grid)
    u̅ᶜᶜᶠ = ℑxzᶜᵃᶠ(i, j, k, grid, uᵖ) * Δt / Δxᶜᶜᶠ(i, j, k, grid)
    v̅ᶠᶜᶜ = ℑxyᶠᶜᵃ(i, j, k, grid, vᵖ) * Δt / Δyᶠᶜᶜ(i, j, k, grid) 
    v̅ᶜᶜᶠ = ℑyzᶜᵃᶠ(i, j, k, grid, vᵖ) * Δt / Δyᶜᶜᶠ(i, j, k, grid)  
    w̅ᶠᶜᶜ = ℑxzᶠᵃᶜ(i, j, k, grid, wᵖ) * Δt / Δzᶠᶜᶜ(i, j, k, grid)  
    w̅ᶜᶠᶜ = ℑyzᵃᶠᶜ(i, j, k, grid, wᵖ) * Δt / Δzᶜᶠᶜ(i, j, k, grid)  

    ξ = u_abs * (1 - u̅ᶠᶜᶜ) * Aᶠᶜᶜ - uᵖ[i, j, k] * v̅ᶠᶜᶜ * Bᶠᶜᶜ - uᵖ[i, j, k] * w̅ᶠᶜᶜ * Cᶠᶜᶜ
    η = v_abs * (1 - v̅ᶜᶠᶜ) * Bᶜᶠᶜ - vᵖ[i, j, k] * u̅ᶜᶠᶜ * Aᶜᶠᶜ - vᵖ[i, j, k] * w̅ᶠᶜᶜ * Cᶜᶠᶜ
    ζ = w_abs * (1 - w̅ᶜᶜᶠ) * Cᶜᶜᶠ - wᵖ[i, j, k] * u̅ᶜᶜᶠ * Aᶜᶜᶠ - wᵖ[i, j, k] * v̅ᶜᶜᶠ * Bᶜᶜᶠ

    return ξ, η, ζ
end

# The actual MPData correction
@kernel function _update_tracer!(c, scheme, pseudo_velocities, grid, divUc, Δt)
    i, j, k = @index(Global, NTuple)

    ∇uc = divUc(i, j, k, grid, scheme, pseudo_velocities, c)
    @inbounds c[i, j, k] -= Δt * ∇uc
end

# Vertical does not matter at the moment!
@inline function div_𝐯u(i, j, k, grid, advection::PartialMPData, U, u)
    return 1/Vᶠᶜᶜ(i, j, k, grid) * (δxᶠᵃᵃ(i, j, k, grid, _advective_momentum_flux_Uu, advection,  U[1], u) +
                                    δyᵃᶜᵃ(i, j, k, grid, _advective_momentum_flux_Vu, advection,  U[2], u) +
                                    δzᵃᵃᶜ(i, j, k, grid, _advective_momentum_flux_Wu, advection.vertical_advection, U[3], u))
end

@inline function div_𝐯v(i, j, k, grid, advection::PartialMPData, U, v)
    return 1/Vᶜᶠᶜ(i, j, k, grid) * (δxᶜᵃᵃ(i, j, k, grid, _advective_momentum_flux_Uv, advection,  U[1], v) +
                                    δyᵃᶠᵃ(i, j, k, grid, _advective_momentum_flux_Vv, advection,  U[2], v) +
                                    δzᵃᵃᶜ(i, j, k, grid, _advective_momentum_flux_Wv, advection.vertical_advection, U[3], v))
end