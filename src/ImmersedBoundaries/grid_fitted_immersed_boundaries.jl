using Adapt
using CUDA: CuArray
using Oceananigans.Fields: fill_halo_regions!
using Oceananigans.Architectures: arch_array

import Oceananigans.Operators: ∂xᶜᵃᵃ, ∂xᶠᵃᵃ, ∂xᶠᶜᵃ, ∂xᶜᶠᵃ, ∂xᶠᶠᵃ, ∂xᶜᶜᵃ, 
                               ∂yᵃᶜᵃ, ∂yᵃᶠᵃ, ∂yᶠᶜᵃ, ∂yᶜᶠᵃ, ∂yᶠᶠᵃ, ∂yᶜᶜᵃ,  
                               ∂zᵃᵃᶜ, ∂zᵃᵃᶠ

import Oceananigans.TurbulenceClosures: ivd_upper_diagonal,
                                        ivd_lower_diagonal


abstract type AbstractGridFittedBoundary <: AbstractImmersedBoundary end

const GFIBG = ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:AbstractGridFittedBoundary}

#####
##### GridFittedBoundary
#####

struct GridFittedBoundary{S} <: AbstractGridFittedBoundary
    mask :: S
end

@inline is_immersed(i, j, k, underlying_grid, ib::GridFittedBoundary) = ib.mask(node(c, c, c, i, j, k, underlying_grid)...)

#####
##### GridFittedBottom
#####

"""
    GridFittedBottom(bottom)

Return an immersed boundary...
"""
struct GridFittedBottom{B} <: AbstractGridFittedBoundary
    bottom :: B
end

@inline function is_immersed(i, j, k, underlying_grid, ib::GridFittedBottom)
    x, y, z = node(c, c, c, i, j, k, underlying_grid)
    return z < ib.bottom(x, y)
end

@inline function is_immersed(i, j, k, underlying_grid, ib::GridFittedBottom{<:AbstractArray})
    x, y, z = node(c, c, c, i, j, k, underlying_grid)
    return @inbounds z < ib.bottom[i, j]
end

const ArrayGridFittedBottom = GridFittedBottom{<:Array}
const CuArrayGridFittedBottom = GridFittedBottom{<:CuArray}

function ImmersedBoundaryGrid(grid, ib::Union{ArrayGridFittedBottom, CuArrayGridFittedBottom})
    # Wrap bathymetry in an OffsetArray with halos
    arch = grid.architecture
    bottom_field = Field{Center, Center, Nothing}(grid)
    bottom_data = arch_array(arch, ib.bottom)
    bottom_field .= bottom_data
    fill_halo_regions!(bottom_field, arch)
    offset_bottom_array = dropdims(bottom_field.data, dims=3)
    new_ib = GridFittedBottom(offset_bottom_array)
    return ImmersedBoundaryGrid(grid, new_ib)
end

const GFBIBG = ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:GridFittedBottom}
const GMGFIB{LX, LY, LZ} = GridMetricOperation{LX, LY, LZ, <:GFBIBG}

@inline Base.getindex(gm::GMGFIB{LX, LY, LZ}, i, j, k) where {LX, LY, LZ} = ifelse(solid_node(LX(), LY(), LZ(), i, j, k, gm.grid),
                                                                                   zero(eltype(ibg)),
                                                                                   gm.metric(i, j, k, gm.grid.grid))

Adapt.adapt_structure(to, ib::GridFittedBottom) = GridFittedBottom(adapt(to, ib.bottom))     

#####
##### Implicit vertical diffusion
#####

@inline z_solid_node(LX, LY, ::Center, i, j, k, ibg) = solid_node(LX, LY, Face(), i, j, k+1, ibg)
@inline z_solid_node(LX, LY, ::Face, i, j, k, ibg)   = solid_node(LX, LY, Center(), i, j, k, ibg)

# extending the upper and lower diagonal functions of the batched tridiagonal solver

for location in (:upper_, :lower_)
    alt_func = Symbol(:_ivd_, location, :diagonal)
     func    = Symbol( :ivd_, location, :diagonal)
    @eval begin
        @inline function $alt_func(i, j, k, ibg::GFIBG, LX, LY, LZ, clock, Δt, interp_κ, κ)
            return ifelse(z_solid_node(LX, LY, LZ, i, j, k, ibg),
                          zero(eltype(ibg.grid)),
                          $func(i, j, k, ibg.grid, LX, LY, LZ, clock, Δt, interp_κ, κ))
        end

        @inline $func(i, j, k, ibg::GFIBG, LX, LY, LZ::Face, clock, Δt, interp_κ, κ) = 
                $alt_func(i, j, k, ibg, LX, LY, LZ, clock, Δt, interp_κ, κ)
        @inline $func(i, j, k, ibg::GFIBG, LX, LY, LZ::Center, clock, Δt, interp_κ, κ) = 
                $alt_func(i, j, k, ibg, LX, LY, LZ, clock, Δt, interp_κ, κ)
    end
end

# metrics are 0 inside the immersed boundaries. This means that derivatives are broken!
# To avoid NaNs appearing everywhere we must be able to define derivatives also inside or across the immersed boundary

# operators = (:∂xᶜᵃᵃ, :∂xᶠᵃᵃ, :∂xᶠᶜᵃ, :∂xᶜᶠᵃ, :∂xᶠᶠᵃ, :∂xᶜᶜᵃ, 
#              :∂yᵃᶜᵃ, :∂yᵃᶠᵃ, :∂yᶠᶜᵃ, :∂yᶜᶠᵃ, :∂yᶠᶠᵃ, :∂yᶜᶜᵃ,  
#              :∂zᵃᵃᶜ, :∂zᵃᵃᶠ)

# for operator in derivative_operators
#         @eval $operator(i, j, k, ibg::GFIBG, args...) = $operator(i, j, k, ibg.grid, args...)
# end
