using DeepDiffs: deepdiff

# remove things that vary on each run: timestamps, run times, line numbers, repo locations
function remove_variables(str)
    return replace(str,
        # Replace timestamps and times with "0"
        r" timestamp=\\\"[0-9-T:.]*\\\"" => " timestamp=\"0\"",
        r" time=\\\"[0-9]*.[0-9]*\\\"" => " time=\"0\"",
        # Replace tag `value` in a <property> with "0"
        # e.g. "<property name=\"dd_tags[perf.gctime]\" value=\"1.23e-6\"></property>"
        r" value=\"[\d]*[.]?[\d]*?[e]?[-]?[\d]?\"(?=></property>)" => " value=\"0\"",
        # Omit stacktrace info between "Stacktrace" and the line containing "</error>".
        # Stacktraces are version specific.
        r" Stacktrace:[\s\S]*(?=\n\s*</error)" => " Stacktrace:\n [omitted]",
        # Ignore the full path the test file.
        r" at .*/test/_junit_xml_test" => " at path/to/test/_junit_xml_test",
        r" at .*/test/_retry_tests" => " at path/to/test/_retry_tests",
        # Ignore worker pid
        r"on worker [0-9]*" => "on worker 0",
        # Remove backticks (because backticks were added to some error messages in v1.9+).
        r"`" => "",
    )
end

function test_reference(reference, comparison)
    if !isfile(reference)
        @warn "Reference files does not exist" reference
        @test false
        return nothing
    end
    a = remove_variables(read(reference, String))
    b = remove_variables(read(comparison, String))
    if a == b
        @test true
        return nothing
    end
    @warn "Reference and comparison files do not match" reference comparison
    println(deepdiff(a, b))
    if isinteractive()
        println("Update reference file? (y/n) [n]")
        answer = lowercase(strip(readline()))
        if startswith(answer, "y")
            mkpath(dirname(reference))
            cp(comparison, reference; force=true)
            println("Reference file updated. Re-run test.")
        end
    end
    # Fail the test, but keep the output short because we've already showed the diff.
    @test :reference == :comparison
end

@testset "JUnit reference tests" begin
    REF_DIR = joinpath(pkgdir(ReTestItems), "test", "references")
    @testset "retries=0, nworkers=$nworkers" for nworkers in (0, 1)
        mktempdir() do dir
            withenv("RETESTITEMS_REPORT_LOCATION" => dir, "RETESTITEMS_NWORKERS" => nworkers) do
                try # Ignore the fact that the `_junit_xml_test.jl` testset has failures/errors.
                    run(`$(Base.julia_cmd()) --project -e 'using ReTestItems; runtests("_junit_xml_test.jl"; report=true, retries=0)'`)
                catch
                end
                report = only(filter(endswith("xml"), readdir(dir, join=true)))
                test_reference(joinpath(REF_DIR, "junit_xml_test_report.xml"), report)
            end
        end
    end
    @testset "retries=1, nworkers=$nworkers" for nworkers in (0, 1)
        mktempdir() do dir
            withenv("RETESTITEMS_REPORT_LOCATION" => dir, "RETESTITEMS_NWORKERS" => nworkers) do
                try # Ignore the fact that the `_junit_xml_test.jl` testset has failures/errors.
                    run(`$(Base.julia_cmd()) --project -e 'using ReTestItems; runtests("_junit_xml_test.jl"; report=true, retries=1)'`)
                catch
                end
                report = only(filter(endswith("xml"), readdir(dir, join=true)))
                test_reference(joinpath(REF_DIR, "junit_xml_test_report_retries.xml"), report)
            end
        end
    end

    @testset "Correct logs for each retry, nworkers=$nworkers" for nworkers in (0, 1)
        mktempdir() do dir
            withenv("RETESTITEMS_REPORT_LOCATION" => dir, "RETESTITEMS_NWORKERS" => nworkers) do
                try # Ignore the fact that the `_retry_tests.jl` testset has failures/errors.
                    run(`$(Base.julia_cmd()) --project -e 'using ReTestItems; runtests("_retry_tests.jl"; report=true, retries=2)'`)
                catch
                end
                report = only(filter(endswith("xml"), readdir(dir, join=true)))
                test_reference(joinpath(REF_DIR, "retry_tests_report.xml"), report)
            end
        end
    end
end

@testset "JUnit empty report" begin
    empty_report = strip("""
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites timestamp="" time="0.0" tests="0" skipped="0" failures="0" errors="0">
        </testsuites>
        """)
    mktempdir() do dir
        withenv("RETESTITEMS_REPORT_LOCATION" => dir) do
            runtests("_empty_file_test.jl"; report=true)
        end
        report = read(only(filter(endswith("xml"), readdir(dir, join=true))), String)
        @test report == empty_report
    end
end

@testset "Respect `RETESTITEMS_REPORT`" begin
    for report in (true, false)
        mktempdir() do dir
            withenv("RETESTITEMS_REPORT" => report, "RETESTITEMS_REPORT_LOCATION" => dir) do
                runtests("_empty_file_test.jl")
            end
            n_reports = length(filter(endswith("xml"), readdir(dir, join=true)))
            if report
                @test n_reports == 1
            else
                @test n_reports == 0
            end
        end
    end
end

@testset "Set error message appropriately" begin
    using XMLDict
    mktempdir() do dir
        withenv("RETESTITEMS_REPORT_LOCATION" => dir) do
            try # Ignore the fact that the `_junit_error_message_test.jl` testset has failures/errors.
                run(`$(Base.julia_cmd()) --project -e 'using ReTestItems; runtests("_junit_error_message_test.jl"; report=true, retries=0)'`)
            catch
            end
        end
        report = read(only(filter(endswith("xml"), readdir(dir, join=true))), String)
        xmldict = XMLDict.parse_xml(report)
        testcases = xmldict["testsuite"]["testcase"]
        @test length(testcases) == 3
        tc1 = testcases[1]
        @test contains(tc1[:name], "one fail")
        @test startswith(tc1["error"][:message], "Test failed")
        @test tc1[:tests] == "3"
        @test tc1[:errors] == "0"
        @test tc1[:failures] == "1"

        tc2 = testcases[2]
        @test contains(tc2[:name], "one error")
        @test startswith(tc2["error"][:message], "Error during test")
        @test tc2[:tests] == "3"
        @test tc2[:errors] == "1"
        @test tc2[:failures] == "0"

        tc3 = testcases[3]
        @test contains(tc3[:name], "error and failure")
        @test startswith(tc3["error"][:message], "Multiple errors")
        @test tc3[:tests] == "3"
        @test tc3[:errors] == "1"
        @test tc3[:failures] == "1"
    end
end

@testset "JUnit properties / DataDog tags" begin
    # The reference tests ensure the properties are written as we expect,
    # BUT they can't test the values (since they will differ between runs)
    # so here we tests the values are written as expected.
    using ReTestItems: PerfStats, write_dd_tags
    stats = PerfStats(; allocs=1, bytes=8, gctime=42, compile_time=3e10, recompile_time=2e6)
    xml = XMLDict.parse_xml(sprint(write_dd_tags, stats))
    props = xml["property"]
    @test contains(props[1][:name], "bytes")
    @test props[1][:value] == "8"
    @test contains(props[2][:name], "allocs")
    @test props[2][:value] == "1"
    # Time values should be converted from Nanoseconds to Seconds, and printed as floats.
    @test contains(props[3][:name], "gctime")
    @test props[3][:value] == "4.2e-8"
    @test contains(props[4][:name], "compile_time")
    @test props[4][:value] == "30.0"
    @test contains(props[5][:name], "recompile_time")
    @test props[5][:value] == "0.002"
end
