
const c = Center()
const f = Face()

"""
###      Immersed
###    -----------
###   |     ∘     |     ∘ 
###   f     c     f     c
###  i-1   i-1    i     i
###
###     solid_interface(Face(), Center(), Center(), i, 1, 1, grid) = true 
###     solid_node(Face(), Center(), Center(), i, 1, 1, grid)      = false 
###     solid_interface(Face(), Center(), Center(), i, 1, 1, grid) = true 
###     solid_node(Face(), Center(), Center(), i-1, 1, 1, grid)    = true 
###     solid_interface(Center(), Center(), Center(), i, 1, 1, grid) = true 
###     solid_node(Center(), Center(), Center(), i, 1, 1, grid)      = false 
###     solid_interface(Center(), Center(), Center(), i, 1, 1, grid) = true 
###     solid_node(Center(), Center(), Center(), i-1, 1, 1, grid)    = true 
"""
@inline solid_node(LX, LY, LZ, i, j, k, ibg)      = is_immersed(i, j, k, ibg.grid, ibg.immersed_boundary)

@inline solid_node(::Face, LY, LZ, i, j, k, ibg) = is_immersed(i  , j, k, ibg.grid, ibg.immersed_boundary) &
                                                   is_immersed(i-1, j, k, ibg.grid, ibg.immersed_boundary)
@inline solid_node(LX, ::Face, LZ, i, j, k, ibg) = is_immersed(i, j  , k, ibg.grid, ibg.immersed_boundary) &
                                                   is_immersed(i, j-1, k, ibg.grid, ibg.immersed_boundary)
@inline solid_node(LX, LY, ::Face, i, j, k, ibg) = is_immersed(i, j,   k, ibg.grid, ibg.immersed_boundary) &
                                                   is_immersed(i, j, k-1, ibg.grid, ibg.immersed_boundary)

@inline solid_node(::Face, ::Face, LZ, i, j, k, ibg) = solid_node(c, f, c, i, j, k, ibg) & solid_node(c, f, c, i-1, j, k, ibg)
@inline solid_node(::Face, LY, ::Face, i, j, k, ibg) = solid_node(c, c, f, i, j, k, ibg) & solid_node(c, c, f, i-1, j, k, ibg)
@inline solid_node(LX, ::Face, ::Face, i, j, k, ibg) = solid_node(c, f, c, i, j, k, ibg) & solid_node(c, f, c, i, j, k-1, ibg)

@inline solid_node(::Face, ::Face, ::Face, i, j, k, ibg) = solid_node(c, f, f, i, j, k, ibg) & solid_node(c, f, f, i-1, j, k, ibg)

@inline solid_interface(LX, LY, LZ, i, j, k, ibg) = is_immersed(i, j, k, ibg.grid, ibg.immersed_boundary)

@inline solid_interface(::Face, LY, LZ, i, j, k, ibg) = is_immersed(i  , j, k, ibg.grid, ibg.immersed_boundary) |
                                                        is_immersed(i-1, j, k, ibg.grid, ibg.immersed_boundary)
@inline solid_interface(LX, ::Face, LZ, i, j, k, ibg) = is_immersed(i, j  , k, ibg.grid, ibg.immersed_boundary) |
                                                        is_immersed(i, j-1, k, ibg.grid, ibg.immersed_boundary)
@inline solid_interface(LX, LY, ::Face, i, j, k, ibg) = is_immersed(i, j,   k, ibg.grid, ibg.immersed_boundary) |
                                                        is_immersed(i, j, k-1, ibg.grid, ibg.immersed_boundary)

@inline solid_interface(::Face, ::Face, LZ, i, j, k, ibg) = solid_interface(c, f, c, i, j, k, ibg) | solid_interface(c, f, c, i-1, j, k, ibg)
@inline solid_interface(::Face, LY, ::Face, i, j, k, ibg) = solid_interface(c, c, f, i, j, k, ibg) | solid_interface(c, c, f, i-1, j, k, ibg)
@inline solid_interface(LX, ::Face, ::Face, i, j, k, ibg) = solid_interface(c, f, c, i, j, k, ibg) | solid_interface(c, f, c, i, j, k-1, ibg)

@inline solid_interface(::Face, ::Face, ::Face, i, j, k, ibg) = solid_interface(c, f, f, i, j, k, ibg) | solid_interface(c, f, f, i-1, j, k, ibg)



for metric in (
               :Δxᶜᶜᵃ,
               :Δxᶜᶠᵃ,
               :Δxᶠᶠᵃ,
               :Δxᶠᶜᵃ,

               :Δyᶜᶜᵃ,
               :Δyᶜᶠᵃ,
               :Δyᶠᶠᵃ,
               :Δyᶠᶜᵃ,

               :Δzᵃᵃᶠ,
               :Δzᵃᵃᶜ,
               :Δzᶠᶜᶜ,
               :Δzᶜᶠᶜ,

               :Azᶜᶜᵃ,
               :Azᶜᶠᵃ,
               :Azᶠᶠᵃ,
               :Azᶠᶜᵃ,

               :Axᶜᶜᶜ, 
               :Axᶠᶜᶜ,
               :Axᶠᶠᶜ,
               :Axᶜᶠᶜ,
               :Axᶠᶜᶠ,
               :Axᶜᶜᶠ,
               
               :Ayᶜᶜᶜ,
               :Ayᶜᶠᶜ,
               :Ayᶠᶜᶜ,
               :Ayᶠᶠᶜ,
               :Ayᶜᶠᶠ,
               :Ayᶜᶜᶠ,

               :Vᶜᶜᶜ, 
               :Vᶠᶜᶜ,
               :Vᶜᶠᶜ,
               :Vᶜᶜᶠ,
              )

    @eval begin
        import Oceananigans.Operators: $metric
        @inline $metric(i, j, k, ibg::ImmersedBoundaryGrid) = $metric(i, j, k, ibg.grid)
    end
end

