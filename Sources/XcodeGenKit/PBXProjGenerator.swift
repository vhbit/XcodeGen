import Foundation
import PathKit
import xcproj
import JSONUtilities
import Yams
import ProjectSpec

public class PBXProjGenerator {

    let spec: ProjectSpec
    let currentXcodeVersion: String
    let proj: PBXProj
    let sourceGenerator: SourceGenerator
    var targetNativeReferences: [String: String] = [:]
    var targetBuildFiles: [String: (reference: String, buildFile: PBXBuildFile)] = [:]
    var targetFileReferences: [String: String] = [:]
    var topLevelGroups: Set<String> = []
    var carthageFrameworksByPlatform: [String: Set<String>] = [:]
    var frameworkFiles: [String] = []
    var generated = false

    var carthageBuildPath: String {
        return spec.options.carthageBuildPath ?? "Carthage/Build"
    }

    public init(spec: ProjectSpec, currentXcodeVersion: String) {
        self.currentXcodeVersion = currentXcodeVersion
        self.spec = spec
        proj = PBXProj(objectVersion: 46, rootObject: "")
        sourceGenerator = SourceGenerator(spec: spec, generateReference: { self.proj.objects.generateReference($0, $1) }) { (_, _) in }
        sourceGenerator.addObject = { [weak self] (object, reference) in
            self?.addObject(object, reference: reference)
        }
    }

    func addObject(_ object: PBXObject, reference: String) {
        proj.objects.addObject(object, reference: reference)
    }

    public func generate() throws -> (reference: String, project: PBXProj) {
        if generated {
            fatalError("Cannot use PBXProjGenerator to generate more than once")
        }
        generated = true
        for group in spec.fileGroups {
            try sourceGenerator.getFileGroups(path: group)
        }

        let buildConfigs: [(reference: String, config: XCBuildConfiguration)] = spec.configs.map { config in
            let buildSettings = spec.getProjectBuildSettings(config: config)
            var baseConfigurationReference: String?
            if let configPath = spec.configFiles[config.name] {
                baseConfigurationReference = sourceGenerator.getContainedFileReference(path: spec.basePath + configPath)
            }
            return XCBuildConfiguration(name: config.name, baseConfigurationReference: baseConfigurationReference, buildSettings: buildSettings)
        }.map {
            return (reference: proj.objects.generateReference($0, $0.name), config: $0)
        }

        let buildConfigList = XCConfigurationList(buildConfigurations: buildConfigs.map { $0.reference },
                                                  defaultConfigurationName: buildConfigs.first?.config.name ?? "",
                                                  defaultConfigurationIsVisible: 0)

        buildConfigs.forEach { addObject($0.config, reference: $0.reference) }
        let buildConfigListReference = proj.objects.generateReference(buildConfigList, spec.name)
        addObject(buildConfigList, reference: buildConfigListReference)

        for target in spec.targets {
            targetNativeReferences[target.name] = referenceGenerator.generate(PBXNativeTarget.self, target.name)
            let fileReference = PBXFileReference(sourceTree: .buildProductsDir, explicitFileType: target.type.fileExtension, path: target.filename, includeInIndex: 0)
            let fileReferenceReference = proj.objects.generateReference(fileReference, target.name)
            addObject(fileReference, reference: fileReferenceReference)
            targetFileReferences[target.name] = fileReferenceReference
            let buildFile = PBXBuildFile(fileRef: fileReferenceReference)
            let buildFileReference = proj.objects.generateReference(buildFile, fileReferenceReference)
            addObject(buildFile, reference: buildFileReference)
            targetBuildFiles[target.name] = (reference: buildFileReference, buildFile: buildFile)
        }

        let targets = try spec.targets.map(generateTarget)

        let productGroup = PBXGroup(children: Array(targetFileReferences.values), sourceTree: .group, name: "Products")
        let productsGroupReference = proj.objects.generateReference(productGroup, "Products")
        addObject(productGroup, reference: productsGroupReference)
        topLevelGroups.insert(productsGroupReference)

        if !carthageFrameworksByPlatform.isEmpty {
            var platformsReferences: [String] = []
            for (platform, fileReferences) in carthageFrameworksByPlatform {
                let platformGroup = PBXGroup(children: fileReferences.sorted(), sourceTree: .group, name: platform, path: platform)
                let platformGroupReference = proj.objects.generateReference(platformGroup, "Carthage" + platform)
                addObject(platformGroup, reference: platformGroupReference)
                platformsReferences.append(platformGroupReference)
            }
            let carthageGroup = PBXGroup(children: platformsReferences.sorted(), sourceTree: .group, name: "Carthage", path: carthageBuildPath)
            let carthageGroupReference = proj.objects.generateReference(carthageGroup, "Carthage")
            addObject(carthageGroup, reference: carthageGroupReference)
            frameworkFiles.append(carthageGroupReference)
        }

        if !frameworkFiles.isEmpty {
            let group = PBXGroup(children: frameworkFiles, sourceTree: .group, name: "Frameworks")
            let groupReference = proj.objects.generateReference(group, "Frameworks")
            addObject(group, reference: groupReference)
            topLevelGroups.insert(groupReference)
        }

        for rootGroup in sourceGenerator.rootGroups {
            topLevelGroups.insert(rootGroup)
        }

        let mainGroup = PBXGroup(children: Array(topLevelGroups), sourceTree: .group)
        let mainGroupReference = proj.objects.generateReference(mainGroup, "Project")
        addObject(mainGroup, reference: mainGroupReference)

        sortGroups(group: mainGroup, reference: mainGroupReference)

        let projectAttributes: [String: Any] = ["LastUpgradeCheck": currentXcodeVersion].merged(spec.attributes)
        let root = PBXProject(name: spec.name,
                              buildConfigurationList: buildConfigListReference,
                              compatibilityVersion: "Xcode 3.2",
                              mainGroup: mainGroupReference,
                              developmentRegion: spec.options.developmentLanguage ?? "en",
                              knownRegions: sourceGenerator.knownRegions.sorted(),
                              targets: targets.map({ $0.reference }),
                              attributes: projectAttributes)
        let rootReference = proj.objects.generateReference(root, spec.name)
        proj.objects.projects.append(root, reference: rootReference)
        proj.rootObject = rootReference
        return (reference: rootReference, project: proj)
    }

    func sortGroups(group: PBXGroup, reference: String) {
        // sort children
        let children = group.children
            .flatMap { reference in
                return proj.objects.getFileElement(reference: reference).flatMap({ (reference: reference, object: $0) })
            }
            .sorted { child1, child2 in
                if child1.object.sortOrder == child2.object.sortOrder {
                    return child1.object.nameOrPath < child2.object.nameOrPath
                } else {
                    return child1.object.sortOrder < child2.object.sortOrder
                }
            }
        group.children = children.map { $0.reference }.filter { $0 != reference }

        // sort sub groups
        let childGroups = group.children.flatMap { reference in
            return proj.objects.groups[reference].flatMap({(group: $0, reference: reference)})
        }
        childGroups.forEach({ sortGroups(group: $0.group, reference: $0.reference) })
    }

    func generateTarget(_ target: Target) throws -> (reference: String, nativeTarget: PBXNativeTarget) {

        sourceGenerator.targetName = target.name
        let carthageDependencies = getAllCarthageDependencies(target: target)

        let sourceFiles = try sourceGenerator.getAllSourceFiles(sources: target.sources)

        // find all Info.plist files
        let infoPlists: [Path] = target.sources.map { spec.basePath + $0.path }.flatMap { (path) -> [Path] in
            if path.isFile {
                if path.lastComponent == "Info.plist" {
                    return [path]
                }
            } else {
                if let children = try? path.recursiveChildren() {
                    return children.filter { $0.lastComponent == "Info.plist" }
                }
            }
            return []
        }

        let configs: [(reference: String, configuration: XCBuildConfiguration)] = spec.configs.map { config in
            var buildSettings = spec.getTargetBuildSettings(target: target, config: config)

            // automatically set INFOPLIST_FILE path
            if let plistPath = infoPlists.first,
                !spec.targetHasBuildSetting("INFOPLIST_FILE", basePath: spec.basePath, target: target, config: config) {
                buildSettings["INFOPLIST_FILE"] = plistPath.byRemovingBase(path: spec.basePath)
            }

            // automatically calculate bundle id
            if let bundleIdPrefix = spec.options.bundleIdPrefix,
                !spec.targetHasBuildSetting("PRODUCT_BUNDLE_IDENTIFIER", basePath: spec.basePath, target: target, config: config) {
                let characterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-.")).inverted
                let escapedTargetName = target.name.replacingOccurrences(of: "_", with: "-").components(separatedBy: characterSet).joined(separator: "")
                buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] = bundleIdPrefix + "." + escapedTargetName
            }

            // automatically set test target name
            if target.type == .uiTestBundle,
                !spec.targetHasBuildSetting("TEST_TARGET_NAME", basePath: spec.basePath, target: target, config: config) {
                for dependency in target.dependencies {
                    if dependency.type == .target,
                        let dependencyTarget = spec.getTarget(dependency.reference),
                        dependencyTarget.type == .application {
                        buildSettings["TEST_TARGET_NAME"] = dependencyTarget.name
                        break
                    }
                }
            }

            // set Carthage search paths
            if !carthageDependencies.isEmpty {
                let frameworkSearchPaths = "FRAMEWORK_SEARCH_PATHS"
                let carthagePlatformBuildPath = "$(PROJECT_DIR)/" + getCarthageBuildPath(platform: target.platform)
                var newSettings: [String] = []
                if var array = buildSettings[frameworkSearchPaths] as? [String] {
                    array.append(carthagePlatformBuildPath)
                    buildSettings[frameworkSearchPaths] = array
                } else if let string = buildSettings[frameworkSearchPaths] as? String {
                    buildSettings[frameworkSearchPaths] = [string, carthagePlatformBuildPath]
                } else {
                    buildSettings[frameworkSearchPaths] = ["$(inherited)", carthagePlatformBuildPath]
                }
            }

            var baseConfigurationReference: String?
            if let configPath = target.configFiles[config.name] {
                baseConfigurationReference = sourceGenerator.getContainedFileReference(path: spec.basePath + configPath)
            }
            let configuration = XCBuildConfiguration(name: config.name, baseConfigurationReference: baseConfigurationReference, buildSettings: buildSettings)
            let configurationReference = proj.objects.generateReference(configuration, config.name + target.name)
            return (reference: configurationReference, configuration: configuration)
        }
        configs.forEach({ addObject($0.configuration, reference: $0.reference)})
        
        let buildConfigList = XCConfigurationList(buildConfigurations: configs.map({$0.reference}), defaultConfigurationName: "")
        let buildConfigurationListReference = proj.objects.generateReference(buildConfigList, target.name)
        addObject(buildConfigList, reference: buildConfigurationListReference)

        var dependencies: [String] = []
        var targetFrameworkBuildFiles: [String] = []
        var copyFrameworksReferences: [String] = []
        var copyResourcesReferences: [String] = []
        var copyWatchReferences: [String] = []
        var extensions: [String] = []

        for dependency in target.dependencies {

            let embed = dependency.embed ?? (target.type.isApp ? true : false)
            switch dependency.type {
            case .target:
                let dependencyTargetName = dependency.reference
                guard let dependencyTarget = spec.getTarget(dependencyTargetName) else { continue }
                let dependencyFileReference = targetFileReferences[dependencyTargetName]!

                let targetProxy = PBXContainerItemProxy(containerPortal: proj.rootObject, remoteGlobalIDString: targetNativeReferences[dependencyTargetName]!, proxyType: .nativeTarget, remoteInfo: dependencyTargetName)
                let targetProxyReference = proj.objects.generateReference(targetProxy, target.name)
                let targetDependency = PBXTargetDependency(target: targetNativeReferences[dependencyTargetName]!, targetProxy: targetProxyReference)
                let targetDependencyReference = proj.objects.generateReference(targetDependency, dependencyTargetName + target.name)
                addObject(targetProxy, reference: targetProxyReference)
                addObject(targetDependency, reference: targetProxyReference)
                dependencies.append(targetDependencyReference)

                if (dependencyTarget.type.isLibrary || dependencyTarget.type.isFramework) && dependency.link {
                    let dependencyBuildFile = targetBuildFiles[dependencyTargetName]!
                    let buildFile = PBXBuildFile(fileRef: dependencyBuildFile.buildFile.fileRef!)
                    let buildFileReference = proj.objects.generateReference(buildFile, dependencyBuildFile.reference + target.name)
                    addObject(buildFile, reference: buildFileReference)
                    targetFrameworkBuildFiles.append(buildFileReference)
                }

                if embed && !dependencyTarget.type.isLibrary {

                    let embedSettings = dependency.buildSettings
                    let embedFile = PBXBuildFile(fileRef: dependencyFileReference, settings: embedSettings)
                    let embedFileReference = proj.objects.generateReference(embedFile, dependencyFileReference + target.name)
                    addObject(embedFile, reference: embedFileReference)

                    if dependencyTarget.type.isExtension {
                        // embed app extension
                        extensions.append(embedFileReference)
                    } else if dependencyTarget.type.isFramework {
                        copyFrameworksReferences.append(embedFileReference)
                    } else if dependencyTarget.type.isApp && dependencyTarget.platform == .watchOS {
                        copyWatchReferences.append(embedFileReference)
                    } else {
                        copyResourcesReferences.append(embedFileReference)
                    }
                }

            case .framework:
                let fileReference: String
                if dependency.implicit {
                    fileReference = sourceGenerator.getFileReference(path: Path(dependency.reference), inPath: spec.basePath, sourceTree: .buildProductsDir)
                } else {
                    fileReference = sourceGenerator.getFileReference(path: Path(dependency.reference), inPath: spec.basePath)
                }

                let buildFile = PBXBuildFile(fileRef: fileReference)
                let buildFileReference = proj.objects.generateReference(buildFile, fileReference + target.name)
                addObject(buildFile, reference: buildFileReference)
                targetFrameworkBuildFiles.append(buildFileReference)
                if !frameworkFiles.contains(fileReference) {
                    frameworkFiles.append(fileReference)
                }

                if embed {
                    let embedFile = PBXBuildFile(fileRef: fileReference, settings: dependency.buildSettings)
                    let embedFileReference = proj.objects.generateReference(embedFile, fileReference + target.name)
                    addObject(embedFile, reference: embedFileReference)
                    copyFrameworksReferences.append(embedFileReference)
                }
            case .carthage:
                var platformPath = Path(getCarthageBuildPath(platform: target.platform))
                var frameworkPath = platformPath + dependency.reference
                if frameworkPath.extension == nil {
                    frameworkPath = Path(frameworkPath.string + ".framework")
                }
                let fileReference = sourceGenerator.getFileReference(path: frameworkPath, inPath: platformPath)

                let buildFile = PBXBuildFile(fileRef: fileReference)
                let buildFileReference = proj.objects.generateReference(buildFile, fileReference + target.name)
                addObject(buildFile, reference: buildFileReference)
                carthageFrameworksByPlatform[target.platform.carthageDirectoryName, default: []].insert(fileReference)

                targetFrameworkBuildFiles.append(buildFileReference)
                if target.platform == .macOS && target.type.isApp {
                    let embedFile = PBXBuildFile(fileRef: fileReference, settings: dependency.buildSettings)
                    let embedFileReference = proj.objects.generateReference(embedFile, fileReference + target.name)
                    addObject(embedFile, reference: embedFileReference)
                    copyFrameworksReferences.append(embedFileReference)
                }
            }
        }

        let fileReference = targetFileReferences[target.name]!
        var buildPhases: [String] = []

        func getBuildFilesForPhase(_ buildPhase: BuildPhase) -> [String] {
            let files = sourceFiles
                .filter { $0.buildPhase == buildPhase }
                .sorted { $0.path.lastComponent < $1.path.lastComponent }
            files.forEach { addObject($0.buildFile, reference: $0.reference) }
            return files.map { $0.reference }
        }

        func getBuildScript(buildScript: BuildScript) throws -> PBXShellScriptBuildPhase {

            let shellScript: String
            switch buildScript.script {
            case let .path(path):
                shellScript = try (spec.basePath + path).read()
            case let .script(script):
                shellScript = script
            }

            let shellScriptPhase = PBXShellScriptBuildPhase(
                files: [],
                name: buildScript.name ?? "Run Script",
                inputPaths: buildScript.inputFiles,
                outputPaths: buildScript.outputFiles,
                shellPath: buildScript.shell ?? "/bin/sh",
                shellScript: shellScript)
            let shellScriptPhaseReference = proj.objects.generateReference(shellScriptPhase, String(describing: buildScript.name) + shellScript + target.name)
            shellScriptPhase.runOnlyForDeploymentPostprocessing = buildScript.runOnlyWhenInstalling ? 1 : 0
            addObject(shellScriptPhase, reference: shellScriptPhaseReference)
            buildPhases.append(shellScriptPhaseReference)
            return shellScriptPhase
        }

        _ = try target.prebuildScripts.map(getBuildScript)

        let sourcesBuildPhaseFiles = getBuildFilesForPhase(.sources)
        if !sourcesBuildPhaseFiles.isEmpty {
            let sourcesBuildPhase = PBXSourcesBuildPhase(files: sourcesBuildPhaseFiles)
            let sourcesBuildPhaseReference = proj.objects.generateReference(sourcesBuildPhase, target.name)
            addObject(sourcesBuildPhase, reference: sourcesBuildPhaseReference)
            buildPhases.append(sourcesBuildPhaseReference)
        }

        let resourcesBuildPhaseFiles = getBuildFilesForPhase(.resources) + copyResourcesReferences
        if !resourcesBuildPhaseFiles.isEmpty {
            let resourcesBuildPhase = PBXResourcesBuildPhase(files: resourcesBuildPhaseFiles)
            let resourcesBuildPhaseReference = proj.objects.generateReference(resourcesBuildPhase, target.name)
            addObject(resourcesBuildPhase, reference: resourcesBuildPhaseReference)
            buildPhases.append(resourcesBuildPhaseReference)
        }

        let headersBuildPhaseFiles = getBuildFilesForPhase(.headers)
        if !headersBuildPhaseFiles.isEmpty && (target.type == .framework || target.type == .dynamicLibrary) {
            let headersBuildPhase = PBXHeadersBuildPhase(files: headersBuildPhaseFiles)
            let headersBuildPhaseReference = proj.objects.generateReference(headersBuildPhase, target.name)
            addObject(headersBuildPhase, reference: headersBuildPhaseReference)
            buildPhases.append(headersBuildPhaseReference)
        }

        if !targetFrameworkBuildFiles.isEmpty {
            let frameworkBuildPhase = PBXFrameworksBuildPhase(
                files: targetFrameworkBuildFiles,
                runOnlyForDeploymentPostprocessing: 0)
            let frameworksBuildPhaseReference = proj.objects.generateReference(frameworkBuildPhase, target.name)
            addObject(frameworkBuildPhase, reference: frameworksBuildPhaseReference)
            buildPhases.append(frameworksBuildPhaseReference)
        }

        if !extensions.isEmpty {
            let copyFilesPhase = PBXCopyFilesBuildPhase(
                dstPath: "",
                dstSubfolderSpec: .plugins,
                files: extensions)
            let copyFilesPhaseReference = proj.objects.generateReference(copyFilesPhase, "embed app extensions" + target.name)
            addObject(copyFilesPhase, reference: copyFilesPhaseReference)
            buildPhases.append(copyFilesPhaseReference)
        }

        if !copyFrameworksReferences.isEmpty {
            let copyFilesPhase = PBXCopyFilesBuildPhase(
                dstPath: "",
                dstSubfolderSpec: .frameworks,
                files: copyFrameworksReferences)
            let copyFilesPhaseReference = proj.objects.generateReference(copyFilesPhase, "embed frameworks" + target.name)
            addObject(copyFilesPhase, reference: copyFilesPhaseReference)
            buildPhases.append(copyFilesPhaseReference)
        }

        if !copyWatchReferences.isEmpty {
            let copyFilesPhase = PBXCopyFilesBuildPhase(
                dstPath: "$(CONTENTS_FOLDER_PATH)/Watch",
                dstSubfolderSpec: .productsDirectory,
                files: copyWatchReferences)
            let copyFilesPhaseReference = proj.objects.generateReference(copyFilesPhase, "embed watch content" + target.name)
            addObject(copyFilesPhase, reference: copyFilesPhaseReference)
            buildPhases.append(copyFilesPhaseReference)
        }

        let carthageFrameworksToEmbed = Array(Set(carthageDependencies
                .filter { $0.embed ?? true }
                .map { $0.reference }))
            .sorted()

        if !carthageFrameworksToEmbed.isEmpty {

            if target.type.isApp && target.platform != .macOS {
                let inputPaths = carthageFrameworksToEmbed.map { "$(SRCROOT)/\(carthageBuildPath)/\(target.platform)/\($0)\($0.contains(".") ? "" : ".framework")" }
                let outputPaths = carthageFrameworksToEmbed.map { "$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/\($0)\($0.contains(".") ? "" : ".framework")" }
                let carthageScript = PBXShellScriptBuildPhase(files: [], name: "Carthage", inputPaths: inputPaths, outputPaths: outputPaths, shellPath: "/bin/sh", shellScript: "/usr/local/bin/carthage copy-frameworks\n")
                let carthageScriptReference = proj.objects.generateReference(carthageScript, "Carthage" + target.name)
                addObject(carthageScript, reference: carthageScriptReference)
                buildPhases.append(carthageScriptReference)
            }
        }

        _ = try target.postbuildScripts.map(getBuildScript)

        let nativeTarget = PBXNativeTarget(
            name: target.name,
            buildConfigurationList: buildConfigurationListReference,
            buildPhases: buildPhases,
            buildRules: [],
            dependencies: dependencies,
            productReference: fileReference,
            productType: target.type)
        let nativeTargetReference = targetNativeReferences[target.name]!
        addObject(nativeTarget, reference: nativeTargetReference)
        return (reference: nativeTargetReference, nativeTarget: nativeTarget)
    }

    func getCarthageBuildPath(platform: Platform) -> String {

        let carthagePath = Path(carthageBuildPath)
        let platformName = platform.carthageDirectoryName
        return "\(carthagePath)/\(platformName)"
    }

    func getAllCarthageDependencies(target: Target, visitedTargets: [String: Bool] = [:]) -> [Dependency] {

        // this is used to resolve cyclical target dependencies
        var visitedTargets = visitedTargets
        visitedTargets[target.name] = true

        var frameworks: [Dependency] = []

        for dependency in target.dependencies {
            switch dependency.type {
            case .carthage:
                frameworks.append(dependency)
            case .target:
                let targetName = dependency.reference
                if visitedTargets[targetName] == true {
                    return []
                }
                if let target = spec.getTarget(targetName) {
                    frameworks += getAllCarthageDependencies(target: target, visitedTargets: visitedTargets)
                }
            default: break
            }
        }
        return frameworks
    }
}
