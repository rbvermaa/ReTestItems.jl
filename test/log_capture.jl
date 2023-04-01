using ReTestItems, Test
@testset "log capture" begin
    PROJECT_PATH = pkgdir(ReTestItems)
    LOG_CAPTURE_TESTS_PATH = joinpath(pkgdir(ReTestItems), "test", "_test_log_capture.jl")

    @testset "$log_display" for log_display in (:eager, :batched, :issues)
        # Need to run in a separate process to force --color=yes in CI.
        cmd = addenv(`$(Base.julia_cmd()) --project=$PROJECT_PATH --color=yes $LOG_CAPTURE_TESTS_PATH`, "LOG_DISPLAY" => log_display)
        p = run(pipeline(ignorestatus(cmd); stdout, stderr), wait=false)
        wait(p)
        @test success(p)
    end
end

@testset "log capture -- reporting" begin
    setup1 = @testsetup module TheTestSetup1 end
    setup2 = @testsetup module TheTestSetup2 end
    ti = @testitem "TheTestItem" setup=[TheTestSetup1, TheTestSetup2] begin end
    push!(ti.testsetups, setup1)
    push!(ti.testsetups, setup2)
    push!(ti.testsets, Test.DefaultTestSet("dummy"))
    setup1.logstore[] = open(ReTestItems.logpath(setup1), "w")
    setup2.logstore[] = open(ReTestItems.logpath(setup2), "w")

    iob = IOBuffer()
    # The test item logs are deleted after `print_errors_and_captured_logs`
    open(io->write(io, "The test item has logs"), ReTestItems.logpath(ti, 1), "w")
    ReTestItems.print_errors_and_captured_logs(iob, ti, 1, logs=:batched)
    logs = String(take!(iob))
    @test contains(logs, " for test item \"TheTestItem\" at ")
    @test contains(logs, "The test item has logs")

    open(io->write(io, "The test item has logs"), ReTestItems.logpath(ti, 1), "w")
    println(setup1.logstore[], "The setup1 also has logs")
    flush(setup1.logstore[])
    ReTestItems.print_errors_and_captured_logs(iob, ti, 1, logs=:batched)
    logs = String(take!(iob))
    @test contains(logs, " for test setup \"TheTestSetup1\" (dependency of \"TheTestItem\") at ")
    @test contains(logs, "The setup1 also has logs")
    @test contains(logs, " for test item \"TheTestItem\" at ")
    @test contains(logs, "The test item has logs")

    open(io->write(io, "The test item has logs"), ReTestItems.logpath(ti, 1), "w")
    println(setup2.logstore[], "Even setup2 has logs!")
    flush(setup2.logstore[])
    ReTestItems.print_errors_and_captured_logs(iob, ti, 1, logs=:batched)
    logs = String(take!(iob))
    @test contains(logs, " for test setup \"TheTestSetup1\" (dependency of \"TheTestItem\") at ")
    @test contains(logs, "The setup1 also has logs")
    @test contains(logs, " for test setup \"TheTestSetup2\" (dependency of \"TheTestItem\") at ")
    @test contains(logs, "Even setup2 has logs!")
    @test contains(logs, " for test item \"TheTestItem\" at ")
    @test contains(logs, "The test item has logs")
end

@testset "default_log_display_mode" begin
    # default_log_display_mode(report::Bool, nworkers::Integer, interactive::Bool)

    @test ReTestItems.default_log_display_mode(false, 0, true) == :eager
    @test ReTestItems.default_log_display_mode(false, 1, true) == :eager
    @test ReTestItems.default_log_display_mode(false, 2, true) == :batched
    @test ReTestItems.default_log_display_mode(false, 3, true) == :batched
    @test_throws AssertionError ReTestItems.default_log_display_mode(false, -1, true)
    @test ReTestItems.default_log_display_mode(false, 0, false) == :issues
    @test ReTestItems.default_log_display_mode(false, 1, false) == :issues
    @test ReTestItems.default_log_display_mode(false, 2, false) == :issues
    @test ReTestItems.default_log_display_mode(false, 3, false) == :issues
    @test_throws AssertionError ReTestItems.default_log_display_mode(false, -1, false)

    @test ReTestItems.default_log_display_mode(true, 0, true) == :batched
    @test ReTestItems.default_log_display_mode(true, 1, true) == :batched
    @test ReTestItems.default_log_display_mode(true, 2, true) == :batched
    @test ReTestItems.default_log_display_mode(true, 3, true) == :batched
    @test_throws AssertionError ReTestItems.default_log_display_mode(true, -1, true)
    @test ReTestItems.default_log_display_mode(true, 0, false) == :issues
    @test ReTestItems.default_log_display_mode(true, 1, false) == :issues
    @test ReTestItems.default_log_display_mode(true, 2, false) == :issues
    @test ReTestItems.default_log_display_mode(true, 3, false) == :issues
    @test_throws AssertionError ReTestItems.default_log_display_mode(true, -1, false)
end