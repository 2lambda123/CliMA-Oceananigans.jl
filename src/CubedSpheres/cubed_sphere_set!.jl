using Oceananigans.Architectures: AbstractCPUArchitecture
using Oceananigans.Fields: AbstractField, ReducedField

import Oceananigans.Fields: set!

const CubedSphereCPUField = CubedSphereField{X, Y, Z, <:AbstractCPUArchitecture} where {X, Y, Z}
const CubedSphereGPUField = CubedSphereField{X, Y, Z, <:AbstractGPUArchitecture} where {X, Y, Z}

function set!(u::CubedSphereCPUField , v::CubedSphereCPUField)
    for (u_face, v_face) in zip(faces(u), faces(v))
        @. u_face.data.parent = v_face.data.parent
    end
    return nothing
end

set!(field::CubedSphereCPUField, f::Function) = [set_face_field!(field_face, f) for field_face in faces(field)]
set!(field::CubedSphereCPUField, f::Number) = [set_face_field!(field_face, f) for field_face in faces(field)]
set!(field::CubedSphereGPUField, f::Function) = [set_face_field!(field_face, f) for field_face in faces(field)]
set!(field::CubedSphereGPUField, f::Number) = [set_face_field!(field_face, f) for field_face in faces(field)]

set_face_field!(field, a) = set!(field, a)

#=
function set_face_field!(field, f::Function)
    LX, LY, LZ = location(field)
    grid = field.grid

    for i in 1:grid.Nx, j in 1:grid.Ny, k in 1:grid.Nz
        λ = λnode(LX(), LY(), LZ(), i, j, k, grid)
        φ = φnode(LX(), LY(), LZ(), i, j, k, grid)
        z = znode(LX(), LY(), LZ(), i, j, k, grid)
        field[i, j, k] = f(λ, φ, z)
    end

    return nothing
end

function set_face_field!(field::ReducedField{LX, LY, Nothing}, f::Function) where {LX, LY}
    grid = field.grid

    for i in 1:grid.Nx, j in 1:grid.Ny
        λ = λnode(LX(), LY(), nothing, i, j, 1, grid)
        φ = φnode(LX(), LY(), nothing, i, j, 1, grid)
        field[i, j, 1] = f(λ, φ)
    end

    return nothing
end
=#
