using Rotations

rotation_from_panel_index(idx) = idx == 1 ? RotX(π/2)*RotY(π/2) :
                                 idx == 2 ? RotY(π)*RotX(-π/2) :
                                 idx == 3 ? RotZ(π) :
                                 idx == 4 ? RotX(π)*RotY(-π/2) :
                                 idx == 5 ? RotY(π/2)*RotX(π/2) :
                                 RotZ(π/2)*RotX(π)
                                    
function MultiRegionGrid(arch::AbstractArchitecture, FT=Float64;
                         panel_size, z,
                         panel_halo = (1, 1, 1),
                         panel_topology = (FullyConnected, FullyConnected, Bounded),
                         radius = R_Earth,
                         partition = CubedSpherePartition(), 
                         devices = nothing)

    devices = validate_devices(partition, arch, devices)
    devices = assign_devices(partition, devices)

    region_size = []
    region_η    = []
    region_ξ    = []
    region_rot  = []
    for r in 1:length(partition)
        Δξ = 2 ./ Rx(r, partition)
        Δη = 2 ./ Ry(r, partition)
        pᵢ = intra_panel_index_x(r, partition)
        pⱼ = intra_panel_index_y(r, partition)
        push!(region_size, (panel_size[1] ÷ Rx(r, partition), panel_size[2] ÷ Ry(r, partition), panel_size[3]))
        push!(region_ξ,    (-1 + Δξ * (pᵢ - 1), -1 + Δξ * pᵢ))
        push!(region_η,    (-1 + Δη * (pⱼ - 1), -1 + Δη * pⱼ))
        push!(region_rot,  rotation_from_panel_index(panel_index(r, partition)))
    end

    region_size = MultiRegionObject(tuple(region_size...), devices)
    region_ξ    = Iterate(region_ξ)
    region_η    = Iterate(region_η)
    region_rot  = Iterate(region_rot)

    region_grids = construct_regionally(OrthogonalSphericalShellGrid, arch, FT; 
                                        size = region_size, 
                                        z, 
                                        halo = panel_halo, 
                                        radius, 
                                        ξ = region_ξ,
                                        η = region_η,
                                        rotation = region_rot)

    return MultiRegionGrid{FT, panel_topology[1], panel_topology[2], panel_topology[3]}(arch, partition, region_grids, devices)
end

"""
Constructing a MultiRegionGrid
grid = MultiRegionGrid(CPU(); partition = CubedSpherePartition(), panel_size = (10, 10, 1), z = (0, 1), radius = 1.0)

to set a field

field = CenterField(grid)

@apply_regionally set!(field, (x, y, z) -> y)

field_panel_1 = getregion(field, 1)

julia> field = CenterField(grid)
dse^R 
10×10×1 Field{Center, Center, Center} on MultiRegionGrid on CPU
├── grid: MultiRegionGrid{Float64, FullyConnected, FullyConnected, Bounded} with CubedSpherePartition{Int64, Int64} on OrthogonalSphericalShellGrid
├── boundary conditions: MultiRegionObject{NTuple{6, FieldBoundaryConditions{BoundaryCondition{Oceananigans.BoundaryConditions.Communication, Oceananigans.MultiRegion.CubedSphereConnectivity}, BoundaryCondition{Oceananigans.BoundaryConditions.Communication, Oceananigans.MultiRegion.CubedSphereConnectivity}, BoundaryCondition{Oceananigans.BoundaryConditions.Communication, Oceananigans.MultiRegion.CubedSphereConnectivity}, BoundaryCondition{Oceananigans.BoundaryConditions.Communication, Oceananigans.MultiRegion.CubedSphereConnectivity}, BoundaryCondition{Flux, Nothing}, BoundaryCondition{Flux, Nothing}, BoundaryCondition{Flux, Nothing}}}, NTuple{6, CPU}}
└── data: MultiRegionObject{NTuple{6, OffsetArrays.OffsetArray{Float64, 3, Array{Float64, 3}}}, NTuple{6, CPU}}
    └── max=0.0, min=0.0, mean=0.0

julia> regions = Iterate(Tuple(i for i in 1:24))
    Iterate{NTuple{24, Int64}}((1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24))
    
julia> set!(field, regions)

julia> fill_halo_regions!(field)


"""