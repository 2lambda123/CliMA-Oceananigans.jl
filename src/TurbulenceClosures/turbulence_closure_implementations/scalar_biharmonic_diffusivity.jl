import Oceananigans.Grids: required_halo_size
using Oceananigans.Utils: prettysummary
using Oceananigans: fields

"""
    struct ScalarBiharmonicDiffusivity{F, N, K} <: AbstractScalarBiharmonicDiffusivity{F}

Holds viscosity and diffusivities for models with prescribed isotropic diffusivities.
"""
struct ScalarBiharmonicDiffusivity{F, N, K} <: AbstractScalarBiharmonicDiffusivity{F}
    ν :: N
    κ :: K

    function ScalarBiharmonicDiffusivity{F}(ν::N, κ::K) where {F, N, K}
        return new{F, N, K}(ν, κ)
    end
end

# Aliases that allow specify the floating type, assuming that the discretization is Explicit in time
                    ScalarBiharmonicDiffusivity(FT::DataType;         kwargs...) = ScalarBiharmonicDiffusivity(ThreeDimensionalFormulation(), FT; kwargs...)
            VerticalScalarBiharmonicDiffusivity(FT::DataType=Float64; kwargs...) = ScalarBiharmonicDiffusivity(VerticalFormulation(), FT; kwargs...)
          HorizontalScalarBiharmonicDiffusivity(FT::DataType=Float64; kwargs...) = ScalarBiharmonicDiffusivity(HorizontalFormulation(), FT; kwargs...)
HorizontalDivergenceScalarBiharmonicDiffusivity(FT::DataType=Float64; kwargs...) = ScalarBiharmonicDiffusivity(HorizontalDivergenceFormulation(), FT; kwargs...)

required_halo_size(::ScalarBiharmonicDiffusivity) = 2

"""
    ScalarBiharmonicDiffusivity([formulation=ThreeDimensionalFormulation(), FT=Float64;]
                                ν=0, κ=0,
                                discrete_form = false)

Return a scalar biharmonic diffusivity turbulence closure with viscosity coefficient `ν` and tracer
diffusivities `κ` for each tracer field in `tracers`. If a single `κ` is provided, it is applied to
all tracers. Otherwise `κ` must be a `NamedTuple` with values for every tracer individually.

Arguments
=========

* `formulation`:
  - `HorizontalFormulation()` for diffusivity applied in the horizontal direction(s)
  - `VerticalFormulation()` for diffusivity applied in the vertical direction,
  - `ThreeDimensionalFormulation()` (default) for diffusivity applied isotropically to all directions

* `FT`: the float datatype (default: `Float64`)

Keyword arguments
=================

  - `ν`: Viscosity. `Number`, `AbstractArray`, or `Function(x, y, z, t)`.

  - `κ`: Diffusivity. `Number`, `AbstractArray`, or `Function(x, y, z, t)`, or
         `NamedTuple` of diffusivities with entries for each tracer.

  - `discrete_form`: `Boolean`.
"""
function ScalarBiharmonicDiffusivity(formulation=ThreeDimensionalFormulation(), FT=Float64;
                                     ν=0, κ=0,
                                     discrete_form = false,
                                     loc = (nothing, nothing, nothing),
                                     parameters = nothing)

    ν = convert_diffusivity(FT, ν; discrete_form, loc, parameters)
    κ = convert_diffusivity(FT, κ; discrete_form, loc, parameters)
    return ScalarBiharmonicDiffusivity{typeof(formulation)}(ν, κ)
end

function with_tracers(tracers, closure::ScalarBiharmonicDiffusivity{F}) where {F}
    κ = tracer_diffusivities(tracers, closure.κ)
    return ScalarBiharmonicDiffusivity{F}(closure.ν, κ)
end

const VSB  = ScalarBiharmonicDiffusivity{<:Any, <:DiscreteDiffusionFunction}
const DSB  = ScalarBiharmonicDiffusivity{<:Any, <:Any, <:DiscreteDiffusionFunction}
const DVSB = ScalarBiharmonicDiffusivity{<:Any, <:DiscreteDiffusionFunction, <:DiscreteDiffusionFunction}

function Diffusivityfields(grid, tracer_names, bcs, ::VSB)   
    default_eddy_viscosity_bcs = (; ν = FieldBoundaryConditions(grid, (Center, Center, Center)))
    bcs = merge(default_eddy_viscosity_bcs, bcs)
    return (; ν=CenterField(grid, boundary_conditions=bcs.ν))
end

function Diffusivityfields(grid, tracer_names, bcs, ::DSB) 
    default_diffusivity_bcs = FieldBoundaryConditions(grid, (Center, Center, Center))
    default_κₑ_bcs = NamedTuple(c => default_diffusivity_bcs for c in tracer_names)
    κₑ_bcs = :κₑ ∈ keys(user_bcs) ? merge(default_κₑ_bcs, user_bcs.κₑ) : default_κₑ_bcs

    bcs = merge((; νₑ = default_diffusivity_bcs, κₑ = κₑ_bcs), user_bcs)

    κₑ = NamedTuple(c => CenterField(grid, boundary_conditions=bcs.κₑ[c]) for c in tracer_names)

    return (; κ = κₑ)
end

function Diffusivityfields(grid, tracer_names, bcs, ::DVSB) 
    default_diffusivity_bcs = FieldBoundaryConditions(grid, (Center, Center, Center))
    default_κₑ_bcs = NamedTuple(c => default_diffusivity_bcs for c in tracer_names)
    κₑ_bcs = :κₑ ∈ keys(user_bcs) ? merge(default_κₑ_bcs, user_bcs.κₑ) : default_κₑ_bcs

    bcs = merge((; νₑ = default_diffusivity_bcs, κₑ = κₑ_bcs), user_bcs)

    νₑ = CenterField(grid, boundary_conditions=bcs.νₑ)
    κₑ = NamedTuple(c => CenterField(grid, boundary_conditions=bcs.κₑ[c]) for c in tracer_names)

    return (; ν = νₑ, κ = κₑ)
end

@inline viscosity(closure::ScalarBiharmonicDiffusivity, K) = closure.ν
@inline diffusivity(closure::ScalarBiharmonicDiffusivity, K, ::Val{id}) where id = closure.κ[id]

@inline viscosity(::Union{VSB, DVSB}, K) = K.ν
@inline diffusivity(::Union{DSB, DVSB}, K, ::Val{id}) where id = K.κ[id]

calculate_diffusivities!(diffusivities, closure::ScalarBiharmonicDiffusivity, args...) = nothing

@inline calc_νᶜᶜᶜ(i, j, k, grid, closure::Union{VSB, DVSB}, clock, fields, buoyancy) =
    getdiffusivity(closure.ν, i, j, k, grid, (c, c, c), clock, fields)

@inline calc_κᶜᶜᶜ(i, j, k, grid, closure::Union{DSB, DVSB}, clock, fields, buoyancy, tracer_index) =
    getdiffusivity(closure.κ, i, j, k, grid, (c, c, c), clock, fields)

function calculate_diffusivities!(diffusivity_fields, closure::VSB, args...) 
    arch = model.architecture
    grid = model.grid
    buoyancy = model.buoyancy

    event = launch!(arch, grid, :xyz,
                    calculate_nonlinear_viscosity!,
                    diffusivity_fields.ν, grid, closure, model.clock, fields(model), buoyancy,
                    dependencies = device_event(arch))

    wait(device(arch), event)

    return nothing
end

function calculate_diffusivities!(diffusivity_fields, closure::DSB, args...) 
    arch = model.architecture
    grid = model.grid
    buoyancy = model.buoyancy

    workgroup, worksize = work_layout(grid, :xyz)
    diffusivity_kernel! = calculate_nonlinear_tracer_diffusivity!(device(arch), workgroup, worksize)

    for (tracer_index, κ) in enumerate(diffusivity_fields.κ)
        @inbounds c = tracers[tracer_index]
        event = diffusivity_kernel!(κ, grid, closure, model.clock, fields(model), buoyancy, Val(tracer_index), dependencies=barrier)
        push!(events, event)
    end

    wait(device(arch), event)

    return nothing
end

function calculate_diffusivities!(diffusivities, closure::DVSB, args...) 

    arch = model.architecture
    grid = model.grid
    buoyancy = model.buoyancy

    workgroup, worksize = work_layout(grid, :xyz)
    viscosity_kernel!   = calculate_nonlinear_viscosity!(device(arch), workgroup, worksize)
    diffusivity_kernel! = calculate_nonlinear_tracer_diffusivity!(device(arch), workgroup, worksize)

    barrier = device_event(arch)
    viscosity_event = viscosity_kernel!(diffusivity_fields.ν, grid, closure, model.clock, fields(model), buoyancy, dependencies=barrier)

    events = [viscosity_event]

    for (tracer_index, κ) in enumerate(diffusivity_fields.κ)
        @inbounds c = tracers[tracer_index]
        event = diffusivity_kernel!(κₑ, grid, closure, model.clock, fields(model), buoyancy, Val(tracer_index), dependencies=barrier)
        push!(events, event)
    end

    wait(device(arch), MultiEvent(Tuple(events)))

    return nothing
end

function Base.summary(closure::ScalarBiharmonicDiffusivity)
    F = summary(formulation(closure))

    if closure.κ == NamedTuple()
        summary_str = string("ScalarBiharmonicDiffusivity{$F}(ν=", prettysummary(closure.ν), ")")
    else
        summary_str = string("ScalarBiharmonicDiffusivity{$F}(ν=", prettysummary(closure.ν), ", κ=", prettysummary(closure.κ), ")")
    end

    return summary_str
end

Base.show(io::IO, closure::ScalarBiharmonicDiffusivity) = print(io, summary(closure))
