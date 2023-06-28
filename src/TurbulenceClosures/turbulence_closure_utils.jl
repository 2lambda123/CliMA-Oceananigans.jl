using Oceananigans.Operators

const PossibleDiffusivity = Union{Number, Function, DiscreteDiffusionFunction, AbstractArray}

tracer_diffusivities(tracers, κ::PossibleDiffusivity) = with_tracers(tracers, NamedTuple(), (tracers, init) -> κ)
tracer_diffusivities(tracers, ::Nothing) = nothing

function tracer_diffusivities(tracers, κ::NamedTuple)

    all(name ∈ propertynames(κ) for name in tracers) ||
        throw(ArgumentError("Tracer diffusivities or diffusivity parameters must either be a constants
                            or a `NamedTuple` with a value for every tracer!"))

    return κ
end

convert_diffusivity(FT, κ::Number; kw...) = convert(FT, κ)

function convert_diffusivity(FT, κ; discrete_form=false, loc=(nothing, nothing, nothing), parameters=nothing)
    discrete_form && return DiscreteDiffusionFunction(κ; loc, parameters)
    return κ
end
    
function convert_diffusivity(FT, κ::NamedTuple; discrete_form=false, loc=(nothing, nothing, nothing), parameters=nothing)
    κ_names = propertynames(κ)
    return NamedTuple{κ_names}(Tuple(convert_diffusivity(FT, κi; discrete_form, loc, parameters) for κi in κ))
end

# extend κ kernel to compute also the boundaries 
# Since the viscous calculation is _always_ second order 
# we need just +1 in each direction
@inline function κ_kernel_size(grid, ::AbstractTurbulenceClosure)
    Nx, Ny, Nz = size(grid)
    Tx, Ty, Tz = topology(grid)

    Ax = Tx == Flat ? Nx : Nx + 2 
    Ay = Ty == Flat ? Ny : Ny + 2 
    Az = Tz == Flat ? Nz : Nz + 2

    return (Ax, Ay, Az)
end

@inline function κ_kernel_offsets(grid, ::AbstractTurbulenceClosure)  
    Tx, Ty, Tz = topology(grid)

    Ax = Tx == Flat ? 0 : - 1 
    Ay = Ty == Flat ? 0 : - 1  
    Az = Tz == Flat ? 0 : - 1 

    return (Ax, Ay, Az)
end
