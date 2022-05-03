include("dependencies_for_runtests.jl")

using Statistics
using NCDatasets

using Dates: Millisecond
using Oceananigans: write_output!
using Oceananigans.BoundaryConditions: PBC, FBC, ZFBC, ContinuousBoundaryFunction
using Oceananigans.TimeSteppers: update_state!
using Oceananigans.OutputWriters: construct_output


function test_output_construction(model)

    u, v, w = model.velocities
    set!(model, u=(x, y, z)->y)

    indices1 = (:, :, :)
    indices2 = (1, 2:3, :)

    # First we test fields
    @test construct_output(u, model.grid, indices1, false) isa Field
    @test construct_output(u, model.grid, indices2, false) isa Field

    # Now we test windowed fields
    u_sliced1 = Field(u, indices=indices1)
    u_sliced2 = Field(u, indices=indices2)

    @test construct_output(u_sliced1, model.grid, indices1, false) isa Field
    @test construct_output(u_sliced1, model.grid, indices2, false) isa Field

    @test construct_output(u_sliced2, model.grid, indices1, false) isa Field
    @test construct_output(u_sliced2, model.grid, indices2, false) isa Field

    @test parent(u_sliced2) != parent(construct_output(u_sliced1, model.grid, indices2, false)) # u_sliced2 should have halo regions
    @test parent(u_sliced2) == parent(construct_output(u_sliced1, model.grid, indices2, true)) # both should have halo regions


    # Now we test abstract operations
    op = u^2+v^2

    @test construct_output(op, model.grid, indices1, false) isa Field
    @test construct_output(op, model.grid, indices2, false) isa Field

    op_sliced1 = Field(op, indices=indices1)
    op_sliced2 = Field(op, indices=indices2)
    compute!(op_sliced1)
    compute!(op_sliced2)

    @test construct_output(op_sliced1, model.grid, indices1, false) isa Field
    @test construct_output(op_sliced1, model.grid, indices2, false) isa Field

    @test construct_output(op_sliced2, model.grid, indices1, false) isa Field
    @test construct_output(op_sliced2, model.grid, indices2, false) isa Field

    @test parent(op_sliced2) != parent(construct_output(op_sliced1, model.grid, indices2, false)) # op_sliced2 should have halo regions
    @test parent(op_sliced2) == parent(construct_output(op_sliced1, model.grid, indices2, true)) # both should have halo regions

    return nothing
end


#####
##### WindowedTimeAverage tests
#####

function run_instantiate_windowed_time_average_tests(model)

    set!(model, u = (x, y, z) -> rand())
    u, v, w = model.velocities
    Nx, Ny, Nz = size(u)

    for test_u in (u, view(u, 1:Nx, 1:Ny, 1:Nz))
        u₀ = deepcopy(parent(test_u))
        wta = WindowedTimeAverage(test_u, schedule=AveragedTimeInterval(10, window=1))
        @test all(wta(model) .== u₀)
    end

    return nothing
end

function time_step_with_windowed_time_average(model)

    model.clock.iteration = 0
    model.clock.time = 0.0

    set!(model, u=0, v=0, w=0, T=0, S=0)

    wta = WindowedTimeAverage(model.velocities.u, schedule=AveragedTimeInterval(4, window=2))

    simulation = Simulation(model, Δt=1.0, stop_time=4.0)
    simulation.diagnostics[:u_avg] = wta
    run!(simulation)

    return all(wta(model) .== parent(model.velocities.u))
end

#####
##### Dependency adding tests
#####

function dependencies_added_correctly!(model, windowed_time_average, output_writer)

    model.clock.iteration = 0
    model.clock.time = 0.0

    simulation = Simulation(model, Δt=1.0, stop_iteration=1)
    push!(simulation.output_writers, output_writer)
    run!(simulation)

    return windowed_time_average ∈ values(simulation.diagnostics)
end

function test_dependency_adding(model)

    windowed_time_average = WindowedTimeAverage(model.velocities.u, schedule=AveragedTimeInterval(4, window=2))

    output = Dict("time_average" => windowed_time_average)
    attributes = Dict("time_average" => Dict("longname" => "A time average",  "units" => "arbitrary"))
    dimensions = Dict("time_average" => ("xF", "yC", "zC"))

    # JLD2 dependencies test
    jld2_output_writer = JLD2OutputWriter(model, output, schedule=TimeInterval(4), dir=".", filename="test.jld2", overwrite_existing=true)

    windowed_time_average = jld2_output_writer.outputs.time_average
    @test dependencies_added_correctly!(model, windowed_time_average, jld2_output_writer)

    rm("test.jld2")

    # NetCDF dependency test
    netcdf_output_writer = NetCDFOutputWriter(model, output,
                                              schedule = TimeInterval(4),
                                              filename = "test.nc",
                                              output_attributes = attributes,
                                              dimensions = dimensions)

    windowed_time_average = netcdf_output_writer.outputs["time_average"]
    @test dependencies_added_correctly!(model, windowed_time_average, netcdf_output_writer)

    rm("test.nc")

    return nothing
end

function test_creating_and_appending(model, output_writer)

    simulation = Simulation(model, Δt=1, stop_iteration=5)
    output = fields(model)
    filename = "test_creating_and_appending"

    # Create a simulation with `overwrite_existing = true` and run it
    simulation.output_writers[:writer] = writer = output_writer(model, output,
                                                                filename = filename,
                                                                schedule = IterationInterval(1),
                                                                overwrite_existing = true, verbose=true)
    run!(simulation)

    # Test if file was crated
    filepath = writer.filepath
    @test isfile(filepath)

    # Extend simulation and run it with `overwrite_existing = false`
    simulation.stop_iteration = 10
    simulation.output_writers[:writer].overwrite_existing = false
    run!(simulation)

    # Test that length is what we expected
    if output_writer === NetCDFOutputWriter
        ds = NCDataset(filepath)
        time_length = length(ds["time"])
    elseif output_writer === JLD2OutputWriter
        ds = jldopen(filepath)
        time_length = length(keys(ds["timeseries/t"]))
    end
    close(ds)
    @test time_length == 11

    rm(filepath)

    return nothing
end

#####
##### Test time averaging of output
#####

function test_windowed_time_averaging_simulation(model)

    jld_filename1 = "test_windowed_time_averaging1.jld2"
    jld_filename2 = "test_windowed_time_averaging2.jld2"

    model.clock.iteration = model.clock.time = 0
    simulation = Simulation(model, Δt=1.0, stop_iteration=0)

    jld2_output_writer = JLD2OutputWriter(model, model.velocities,
                                          schedule = AveragedTimeInterval(π, window=1),
                                          filename = jld_filename1,
                                          overwrite_existing = true)

    # https://github.com/Alexander-Barth/NCDatasets.jl/issues/105
    nc_filepath1 = "windowed_time_average_test1.nc"
    nc_outputs = Dict(string(name) => field for (name, field) in pairs(model.velocities))
    nc_output_writer = NetCDFOutputWriter(model, nc_outputs, filename=nc_filepath1,
                                          schedule = AveragedTimeInterval(π, window=1))

    jld2_outputs_are_time_averaged = Tuple(typeof(out) <: WindowedTimeAverage for out in jld2_output_writer.outputs)
      nc_outputs_are_time_averaged = Tuple(typeof(out) <: WindowedTimeAverage for out in values(nc_output_writer.outputs))

    @test all(jld2_outputs_are_time_averaged)
    @test all(nc_outputs_are_time_averaged)

    # Test that the collection does *not* start when a simulation is initialized
    # when time_interval ≠ time_averaging_window
    simulation.output_writers[:jld2] = jld2_output_writer
    simulation.output_writers[:nc] = nc_output_writer

    run!(simulation)

    jld2_u_windowed_time_average = simulation.output_writers[:jld2].outputs.u
    nc_w_windowed_time_average = simulation.output_writers[:nc].outputs["w"]

    @test !(jld2_u_windowed_time_average.schedule.collecting)
    @test !(nc_w_windowed_time_average.schedule.collecting)

    # Test that time-averaging is finalized prior to output even when averaging over
    # time_window is not fully realized. For this, step forward to a time at which
    # collection should start. Note that time_interval = π and time_window = 1.0.
    simulation.Δt = 1.5
    simulation.stop_iteration = 2
    run!(simulation) # model.clock.time = 3.0, just before output but after average-collection.

    @test jld2_u_windowed_time_average.schedule.collecting
    @test nc_w_windowed_time_average.schedule.collecting

    # Step forward such that time_window is not reached, but output will occur.
    simulation.Δt = π - 3 + 0.01 # ≈ 0.15 < 1.0
    simulation.stop_iteration = 3
    run!(simulation) # model.clock.time ≈ 3.15, after output

    @test jld2_u_windowed_time_average.schedule.previous_interval_stop_time ==
        model.clock.time - rem(model.clock.time, jld2_u_windowed_time_average.schedule.interval)

    @test nc_w_windowed_time_average.schedule.previous_interval_stop_time ==
        model.clock.time - rem(model.clock.time, nc_w_windowed_time_average.schedule.interval)

    # Test that collection does start when a simulation is initialized and
    # time_interval == time_averaging_window
    model.clock.iteration = model.clock.time = 0

    simulation.output_writers[:jld2] = JLD2OutputWriter(model, model.velocities,
                                                        schedule = AveragedTimeInterval(π, window=π),
                                                        filename = jld_filename2,
                                                        overwrite_existing = true)

    nc_filepath2 = "windowed_time_average_test2.nc"
    nc_outputs = Dict(string(name) => field for (name, field) in pairs(model.velocities))
    simulation.output_writers[:nc] = NetCDFOutputWriter(model, nc_outputs, filename=nc_filepath2,
                                                        schedule=AveragedTimeInterval(π, window=π))

    run!(simulation)

    @test simulation.output_writers[:jld2].outputs.u.schedule.collecting
    @test simulation.output_writers[:nc].outputs["w"].schedule.collecting

    rm(nc_filepath1)
    rm(nc_filepath2)
    rm(jld_filename1)
    rm(jld_filename2)

    return nothing
end



#####
##### Run output writer tests!
#####

topo = (Periodic, Periodic, Bounded)
@testset "Output writers" begin
    @info "Testing output writers..."

    for arch in archs
        grid = RectilinearGrid(arch, topology=topo, size=(4, 4, 4), extent=(1, 1, 1))
        model = NonhydrostaticModel(; grid)

        @info "Test that outputs are properly constructed"
        test_output_construction(model)

        @info "Testing that writers create file and append to it properly"
        for output_writer in (NetCDFOutputWriter, JLD2OutputWriter)
            test_creating_and_appending(model, output_writer)
        end

        # Some tests can reuse this same grid and model.
        model = NonhydrostaticModel(grid=grid,
                                    buoyancy=SeawaterBuoyancy(), tracers=(:T, :S))


        @testset "WindowedTimeAverage [$(typeof(arch))]" begin
            @info "  Testing WindowedTimeAverage [$(typeof(arch))]..."
            run_instantiate_windowed_time_average_tests(model)
            @test time_step_with_windowed_time_average(model)
            @test_throws ArgumentError AveragedTimeInterval(1.0, window=1.1)
        end
    end

    include("test_netcdf_output_writer.jl")
    include("test_jld2_output_writer.jl")
    include("test_checkpointer.jl")

    for arch in archs
        grid = RectilinearGrid(arch, topology=topo, size=(4, 4, 4), extent=(1, 1, 1))
        model = NonhydrostaticModel(grid=grid,
                                    buoyancy=SeawaterBuoyancy(), tracers=(:T, :S))

        @testset "Dependency adding [$(typeof(arch))]" begin
            @info "    Testing dependency adding [$(typeof(arch))]..."
            test_dependency_adding(model)
        end

        @testset "Time averaging of output [$(typeof(arch))]" begin
            @info "    Testing time averaging of output [$(typeof(arch))]..."
            test_windowed_time_averaging_simulation(model)
        end
    end
end

