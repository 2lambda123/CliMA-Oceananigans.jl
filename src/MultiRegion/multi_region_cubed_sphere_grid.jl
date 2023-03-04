using Oceananigans.Architectures: architecture
using Oceananigans.Grids: R_Earth, halo_size, size_summary

using Rotations

rotation_from_panel_index(idx) = idx == 1 ? RotX(π/2)*RotY(π/2) :
                                 idx == 2 ? RotY(π)*RotX(-π/2) :
                                 idx == 3 ? RotZ(π) :
                                 idx == 4 ? RotX(π)*RotY(-π/2) :
                                 idx == 5 ? RotY(π/2)*RotX(π/2) :
                                 RotZ(π/2)*RotX(π)

"""
    ConformalCubedSphereGrid(arch::AbstractArchitecture, FT=Float64;
                             panel_size,
                             z,
                             panel_halo = (1, 1, 1),
                             panel_topology = (FullyConnected, FullyConnected, Bounded),
                             radius = R_Earth,
                             partition = CubedSpherePartition(), 
                             devices = nothing)

Return a ConformalCubedSphereGrid.

The connectivity between the `ConformalCubedSphereGrid` faces is 
depicted below.

```
                          +----------+----------+
                          |    ↑↑    |    ↑↑    |
                          |    1W    |    1S    |
                          |←3N P5 6W→|←5E P6 2S→|
                          |    4N    |    4E    |
                          |    ↓↓    |    ↓↓    |
               +----------+----------+----------+
               |    ↑↑    |    ↑↑    |
               |    5W    |    5S    |
               |←1N P3 4W→|←3E P4 6S→|
               |    2N    |    2E    |
               |    ↓↓    |    ↓↓    |
    +----------+----------+----------+
    |    ↑↑    |    ↑↑    |
    |    3W    |    3S    |
    |←5N P1 2W→|←1E P2 4S→|
    |    6N    |    6E    |
    |    ↓↓    |    ↓↓    |
    +----------+----------+
```


By default, the North Pole of the sphere is in panel 1 (P1) and
the South Pole in panel 6 (P6).

A `CubedSpherePartition(; Rx=2)` implies partition in 2 in each
dimension of each panel resulting in 24 regions. In each partition
the intra-panel `x, y` indices are in written in the center and the
overall region index on the bottom right.

```
                                                +==========+==========+==========+==========+
                                                ∥    ↑     |    ↑     ∥    ↑     |    ↑     ∥
                                                ∥          |          ∥          |          ∥
                                                ∥← (1, 2) →|← (2, 2) →∥← (1, 2) →|← (2, 2) →∥
                                                ∥          |          ∥          |          ∥
                                                ∥    ↓  19 |    ↓  20 ∥    ↓  23 |    ↓  24 ∥
                                                +-------- P 5 --------+-------- P 6 --------+
                                                ∥    ↑     |    ↑     ∥    ↑     |    ↑     ∥
                                                ∥          |          ∥          |          ∥
                                                ∥← (1, 1) →|← (2, 1) →∥← (1, 1) →|← (2, 1) →∥
                                                ∥          |          ∥          |          ∥
                                                ∥    ↓  17 |    ↓  18 ∥    ↓  21 |    ↓  22 ∥
                          +==========+==========+==========+==========+==========+==========+
                          ∥    ↑     |    ↑     ∥    ↑     |    ↑     ∥
                          ∥          |          ∥          |          ∥
                          ∥← (1, 2) →|← (2, 2) →∥← (1, 2) →|← (2, 2) →∥
                          ∥          |          ∥          |          ∥
                          ∥    ↓ 11  |    ↓  12 ∥    ↓  15 |    ↓  16 ∥
                          +-------- P 3 --------+-------- P 4 --------+
                          ∥    ↑     |    ↑     ∥    ↑     |    ↑     ∥
                          ∥          |          ∥          |          ∥
                          ∥← (1, 1) →|← (2, 1) →∥← (1, 1) →|← (2, 1) →∥
                          ∥          |          ∥          |          ∥
                          ∥    ↓  9  |    ↓  10 ∥    ↓  13 |    ↓  14 ∥
    +==========+==========+==========+==========+==========+==========+
    ∥    ↑     |    ↑     ∥    ↑     |    ↑     ∥
    ∥          |          ∥          |          ∥
    ∥← (1, 2) →|← (2, 2) →∥← (1, 2) →|← (2, 2) →∥
    ∥          |          ∥          |          ∥
    ∥    ↓   3 |    ↓   4 ∥    ↓   7 |    ↓   8 ∥
    +-------- P 1 --------+-------- P 2 --------+
    ∥    ↑     |    ↑     ∥    ↑     |    ↑     ∥
    ∥          |          ∥          |          ∥
    ∥← (1, 1) →|← (2, 1) →∥← (1, 1) →|← (2, 1) →∥ 
    ∥          |          ∥          |          ∥
    ∥    ↓   1 |    ↓   2 ∥    ↓   5 |    ↓   6 ∥
    +==========+==========+==========+==========+
```

Below, we show in detail panels 1 and 2 and the connectivity
of each panel.

```
+===============+==============+==============+===============+
∥       ↑       |      ↑       ∥      ↑       |      ↑        ∥
∥      11W      |      9W      ∥      9S      |     10S       ∥
∥←19N (2, 1) 4W→|←3E (2, 2) 7W→∥←4E (2, 1) 8W→|←7E (2, 2) 13S→∥
∥       1N      |      2N      ∥      5N      |      6N       ∥
∥       ↓     3 |      ↓     4 ∥      ↓     7 |      ↓      8 ∥
+------------- P 1 ------------+------------ P 2 -------------+
∥       ↑       |      ↑       ∥      ↑       |      ↑        ∥
∥       3S      |      4S      ∥      7S      |      8S       ∥
∥←20N (1, 1) 2W→|←1E (2, 1) 5W→∥←2E (1, 1) 6W→|←5E (2, 1) 14S→∥
∥      23N      |     24N      ∥     24N      |     22N       ∥
∥       ↓     1 |      ↓     2 ∥      ↓     5 |      ↓      6 ∥
+===============+==============+==============+===============+
```

Example
=======

```julia
julia> using Oceananigans

julia> grid = ConformalCubedSphereGrid(panel_size=(10, 10, 1), z=(-1, 0), radius=1.0)
ConformalCubedSphereGrid{Float64, FullyConnected, FullyConnected, Bounded} partitioned on CPU(): 
├── grids: 10×10×1 OrthogonalSphericalShellGrid{Float64, Bounded, Bounded, Bounded} on CPU with 1×1×1 halo and with precomputed metrics 
├── partitioning: CubedSpherePartition with (1 region in each panel) 
└── devices: (CPU(), CPU(), CPU(), CPU(), CPU(), CPU())
```
"""
function ConformalCubedSphereGrid(arch::AbstractArchitecture=CPU(), FT=Float64;
                                  panel_size,
                                  z,
                                  panel_halo = (1, 1, 1),
                                  panel_topology = (FullyConnected, FullyConnected, Bounded),
                                  radius = R_Earth,
                                  partition = CubedSpherePartition(; Rx=1),
                                  devices = nothing)

    devices = validate_devices(partition, arch, devices)
    devices = assign_devices(partition, devices)

    region_size = []
    region_η = []
    region_ξ = []
    region_rotation = []

    for r in 1:length(partition)
        # for a whole cube's face (ξ, η) ∈ [-1, 1]x[-1, 1]
        Δξ = 2 / Rx(r, partition)
        Δη = 2 / Ry(r, partition)

        pᵢ = intra_panel_index_x(r, partition)
        pⱼ = intra_panel_index_y(r, partition)

        push!(region_size, (panel_size[1] ÷ Rx(r, partition), panel_size[2] ÷ Ry(r, partition), panel_size[3]))
        push!(region_ξ, (-1 + Δξ * (pᵢ - 1), -1 + Δξ * pᵢ))
        push!(region_η, (-1 + Δη * (pⱼ - 1), -1 + Δη * pⱼ))
        push!(region_rotation, rotation_from_panel_index(panel_index(r, partition)))
    end

    region_size = MultiRegionObject(tuple(region_size...), devices)
    region_ξ = Iterate(region_ξ)
    region_η = Iterate(region_η)
    region_rotation = Iterate(region_rotation)

    region_grids = construct_regionally(OrthogonalSphericalShellGrid, arch, FT;
                                        size = region_size,
                                        z,
                                        halo = panel_halo,
                                        radius,
                                        ξ = region_ξ,
                                        η = region_η,
                                        rotation = region_rotation)

    return MultiRegionGrid{FT, panel_topology[1], panel_topology[2], panel_topology[3]}(arch, partition, region_grids, devices)
end

"""
    ConformalCubedSphereGrid(filepath::AbstractString, arch::AbstractArchitecture=CPU(), FT=Float64;
                             Nz,
                             z,
                             panel_halo = (1, 1, 1),
                             panel_topology = (FullyConnected, FullyConnected, Bounded),
                             radius = R_Earth,
                             devices = nothing)

Load a ConformalCubedSphereGrid from `filepath`.
"""
function ConformalCubedSphereGrid(filepath::AbstractString, arch::AbstractArchitecture=CPU(), FT=Float64;
                                  Nz,
                                  z,
                                  panel_halo = (1, 1, 1),
                                  panel_topology = (FullyConnected, FullyConnected, Bounded),
                                  radius = R_Earth,
                                  devices = nothing)

    devices = validate_devices(partition, arch, devices)
    devices = assign_devices(partition, devices)

    # to load a ConformalCubedSphereGrid from file we can only have a 6-panel partition
    partition = CubedSpherePartition(; Rx=1)

    region_Nz = MultiRegionObject(Tuple(repeat([Nz], length(partition))), devices)
    region_panels = Iterate(Array(1:length(partition)))

    region_grids = construct_regionally(OrthogonalSphericalShellGrid, filepath, arch, FT;
                                        Nz = region_Nz,
                                        z,
                                        panel = region_panels,
                                        topology = panel_topology,
                                        halo = panel_halo,
                                        radius)

    return MultiRegionGrid{FT, panel_topology[1], panel_topology[2], panel_topology[3]}(arch, partition, region_grids, devices)
end

function Base.summary(grid::MultiRegionGrid{FT, TX, TY, TZ, <:CubedSpherePartition}) where {FT, TX, TY, TZ}
    return string(size_summary(size(grid)),
                  " ConformalCubedSphereGrid{$FT, $TX, $TY, $TZ} on ", summary(architecture(grid)),
                  " with ", size_summary(halo_size(grid)), " halo")
end

Base.show(io::IO, mrg::MultiRegionGrid{FT, TX, TY, TZ, <:CubedSpherePartition}) where {FT, TX, TY, TZ} =
    print(io, "ConformalCubedSphereGrid{$FT, $TX, $TY, $TZ} partitioned on $(architecture(mrg)): \n",
              "├── grids: $(summary(mrg.region_grids[1])) \n",
              "├── partitioning: $(summary(mrg.partition)) \n",
              "└── devices: $(devices(mrg))")

"""
Constructing a MultiRegionGrid

to set a field

field = CenterField(grid)

@apply_regionally set!(field, (x, y, z) -> y)

field_panel_1 = getregion(field, 1)

julia> field = CenterField(grid)
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