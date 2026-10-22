-- Skip SwiftPM manifest compiles: they target macOS, are not app code, and
-- extracting them pulls in the whole macOS SDK. Every other swift-frontend
-- invocation keeps the default Swift matchers.
function GetCompatibleVersions()
    return { '1.0.0' }
end

local function isManifestCompile(compilerName, compilerArguments)
    if compilerName ~= 'swift-frontend' then
        return false
    end
    local macOSTarget, manifest = false, false
    local argv = compilerArguments.argv
    for index, value in ipairs(argv) do
        if value == '-target' and argv[index + 1] and string.find(argv[index + 1], '-apple-macos', 1, true) then
            macOSTarget = true
        end
        if string.find(value, '/Package[^/]*%.swift$') then
            manifest = true
        end
    end
    return macOSTarget and manifest
end

function RegisterExtraConfig()
    local function SkipManifestMatcher(compilerName, compilerPath, compilerArguments, lang)
        if isManifestCompile(compilerName, compilerArguments) then
            return { trace = false }
        end
        return nil
    end
    local matchers = { SkipManifestMatcher }
    for _, matcher in ipairs(GetRegisteredMatchers('swift')) do
        table.insert(matchers, matcher)
    end
    return { swift = matchers }
end
