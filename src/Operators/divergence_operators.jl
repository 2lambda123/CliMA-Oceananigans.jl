abstract type AbstractDivergenceScheme end


#####
##### Divergence operators
#####

"""
    divᶜᶜᶜ(i, j, k, grid, u, v, w)

Calculates the divergence ∇·𝐔 of a vector field 𝐔 = (u, v, w),

    1/V * [δxᶜᵃᵃ(Ax * u) + δxᵃᶜᵃ(Ay * v) + δzᵃᵃᶜ(Az * w)],

which will end up at the cell centers `ccc`.
"""
@inline function divᶜᶜᶜ(i, j, k, grid, u, v, w)
    return 1/Vᶜᶜᶜ(i, j, k, grid) * (δxᶜᵃᵃ(i, j, k, grid, Ax_qᶠᶜᶜ, u) +
                                    δyᵃᶜᵃ(i, j, k, grid, Ay_qᶜᶠᶜ, v) +
                                    δzᵃᵃᶜ(i, j, k, grid, Az_qᶜᶜᶠ, w))
end

#####
##### Schemes for calculating horizontal divergence
#####

struct TrivialSecondOrder <: AbstractHorizontalDivergenceScheme end
struct UpwindWENO4 <: AbstractHorizontalDivergenceScheme end
struct CenteredWENO5 <: AbstractHorizontalDivergenceScheme end

@inline _symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, ::TrivialSecondOrder, u) = @inbounds u[i, j, k]
@inline _symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, ::TrivialSecondOrder, v) = @inbounds v[i, j, k]

"""
    div_xyᶜᶜᵃ(i, j, k, grid, u, v)

Returns the discrete `div_xy = ∂x u + ∂y v` of velocity field `u, v` defined as

```
1 / Azᶜᶜᵃ * [δxᶜᵃᵃ(Δyᵃᶜᵃ * u) + δyᵃᶜᵃ(Δxᶜᵃᵃ * v)]
```

at `i, j, k`, where `Azᶜᶜᵃ` is the area of the cell centered on (Center, Center, Any) --- a tracer cell,
`Δy` is the length of the cell centered on (Face, Center, Any) in `y` (a `u` cell),
and `Δx` is the length of the cell centered on (Center, Face, Any) in `x` (a `v` cell).
`div_xyᶜᶜᵃ` ends up at the location `cca`.
"""
@inline function div_xyᶜᶜᶜ(i, j, k, grid, scheme, u, v)
    ũ  = _symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme, u)
    ṽ  = _symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme, v)

    return 1 / Azᶜᶜᶜ(i, j, k, grid) * (δxᶜᵃᵃ(i, j, k, grid, Δy_qᶠᶜᶜ, ũ) +
                                       δyᵃᶜᵃ(i, j, k, grid, Δx_qᶜᶠᶜ, ṽ))
end

# Default
@inline div_xyᶜᶜᶜ(i, j, k, grid, u, v) = div_xyᶜᶜᶜ(i, j, k, grid, TrivialSecondOrder(), u, v)

