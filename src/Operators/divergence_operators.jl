#####
##### Divergence operators
#####

"""
    divᶜᶜᶜ(i, j, k, grid, u, v, w)

Calculates the divergence ∇·𝐔 of a vector field 𝐔 = (u, v, w),
which ends up at tracer cell centers (ccc).
"""
@inline function divᶜᶜᶜ(i, j, k, grid, u, v, w)
    return 1 / Vᶜᶜᶜ(i, j, k, grid) * (δxᶜᶜᶜ(i, j, k, grid, Ax_qᶠᶜᶜ, u) +
                                      δyᶜᶜᶜ(i, j, k, grid, Ay_qᶜᶠᶜ, v) +
                                      δzᶜᶜᶜ(i, j, k, grid, Az_qᶜᶜᶠ, w))
end

"""
    div_xyᶜᶜᶜ(i, j, k, grid, u, v)

Returns the discrete horizontal divergence `div_xy = ∂x u + ∂y v`
of velocity field `u, v`. `div_xyᶜᶜᶜ` ends up at the location `ccc`.
"""
@inline function div_xyᶜᶜᶜ(i, j, k, grid, u, v)
    return 1 / Azᶜᶜᶜ(i, j, k, grid) * (δxᶜᶜᶜ(i, j, k, grid, Δy_qᶠᶜᶜ, u) +
                                       δyᶜᶜᶜ(i, j, k, grid, Δx_qᶜᶠᶜ, v))
end

#####
##### "Location-less" divergence operator
#####

@inline Base.div(i, j, k, grid::AbstractGrid, loc, q_west, q_east, q_south, q_north, q_bottom, q_top) =
    1 / volume(i, j, k, grid, loc...) * (δx_Ax_q(i, j, k, grid, loc, q_west, q_east) + 
                                         δy_Ay_q(i, j, k, grid, loc, q_south, q_north) + 
                                         δz_Az_q(i, j, k, grid, loc, q_bottom, q_top))
    
@inline function δx_Ax_q(i, j, k, grid, (LX, LY, LZ), qᵂ, qᴱ)
    iᵂ = idxᴸ(i, LX)
    Axᵂ = Ax(iᵂ, j, k, grid, LX, LY, LZ)

    iᴱ = idxᴿ(i, LX)
    Axᴱ = Ax(iᴱ, j, k, grid, LX, LY, LZ)

    return Axᴱ * qᴱ - Axᵂ * qᵂ
end

@inline function δy_Ay_q(i, j, k, grid, (LX, LY, LZ), qˢ, qᴺ)
    jˢ = idxᴸ(j, LY)
    Ayˢ = Ay(i, jˢ, k, grid, LX, LY, LZ)

    jᴺ = idxᴿ(j, LY)
    Ayᴺ = Ay(i, jᴺ, k, grid, LX, LY, LZ)

    return Ayᴺ * qᴺ - Ayˢ * qˢ
end

@inline function δz_Az_q(i, j, k, grid, (LX, LY, LZ), qᴮ, qᵀ)
    kᴮ = idxᴸ(k, LZ)
    Azᴮ = Az(i, j, kᴮ, grid, LX, LY, LZ)

    kᵀ = idxᴿ(k, LZ)
    Azᵀ = Az(i, j, kᵀ, grid, LX, LY, LZ)

    return Azᵀ * qᵀ - Azᴮ * qᴮ
end

# And flat!

@inline δx_Ax_q(i, j, k, grid::XFlatGrid, args...) = zero(grid)
@inline δy_Ay_q(i, j, k, grid::YFlatGrid, args...) = zero(grid)
@inline δz_Az_q(i, j, k, grid::ZFlatGrid, args...) = zero(grid)
