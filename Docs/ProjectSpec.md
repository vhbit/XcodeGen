# Project Spec
The project spec can be written in either YAML or JSON. All the examples below use YAML.

Some of the examples below don't show all the required properties when trying to explain something. For example not all target examples will have a platform or type, even though they are required.

Required properties are marked 🔵 and optional properties with ⚪️.

### Index

- [Project](#project)
	- [Include](#include)
	- [Options](#options)
	- [Configs](#configs)
	- [Setting Groups](#setting-groups)
- [Settings](#settings)
- [Target](#target)
	- [Product Type](#product-type)
	- [Platform](#platform)
	- [Sources](#sources)
	- [Config Files](#config-files)
	- [Settings](#settings)
	- [Build Script](#build-script)
	- [Dependency](#dependency)
	- [Target Scheme](#target-scheme)

## Project

- 🔵 **name**: `String` - Name of the generated project
- ⚪️ **include**: [Include](#include) - One or more paths to other specs
- ⚪️ **options**: [Options](#options) - Various options to override default behaviour
- ⚪️ **attributes**: `map` - The PBXProject attributes. This is for advanced use. Defaults to ``{"LastUpgradeCheck": "0900"}``
- ⚪️ **configs**: [Configs](#configs) - Project build configurations. Defaults to `Debug` and `Release` configs
- ⚪️ **configFiles**: [Config Files](#config-files) - `.xcconfig` files per config
- ⚪️ **settings**: [Settings](#settings) - Project specific settings. Default base and config type settings will be applied first before any settings defined here
- ⚪️ **settingGroups**: [Setting Groups](#setting-groups) - Setting groups mapped by name
- ⚪️ **targets**: [Target](#target) - The list of targets in the project mapped by name
- ⚪️ **fileGroups**: `[String]` - A list of paths to add to the top level groups. These are files that aren't build files but that you'd like in the project hierachy. For example a folder xcconfig files that aren't already added by any target sources.

### Include
One or more specs can be included in the project spec. This can be used to split your project spec into multiple files, for easier structuring or sharing between multiple specs. Included specs can also include other specs and so on.

Include can either be a list of string paths or a single string path. They will be merged in order and then the current spec will be merged on top.
By default specs are merged additively. That is for every value:

- if existing value and new value are both dictionaries merge them and continue down the hierachy
- if existing value and new value are both an array then add the new value to the end of the array
- otherwise replace the existing value with the new value

This merging behaviour can be overriden on a value basis. If you wish to replace a whole value (set a new dictionary or new array instead of merging them) then just affix `:REPLACE` to the key


```yaml
include:
  - base.yml
name: CustomSpec
targets:
  MyTarget: # target lives in base.yml
    sources:REPLACE:
      - my_new_sources
```

Note that target names can also be changed by adding a `name` property to a target.

### Options
- ⚪️ **carthageBuildPath**: `String` - The path to the carthage build directory. Defaults to `Carthage/Build`. This is used when specifying target carthage dependencies
- ⚪️ **createIntermediateGroups**: `Bool` - If this is specified and set to `true`, then intermediate groups will be created for every path component between the folder containing the source and next existing group it finds or the base path. For example, when enabled if a source path is specified as `Vendor/Foo/Hello.swift`, the group `Vendor` will created as a parent of the `Foo` group.
- ⚪️ **bundleIdPrefix**: `String` - If this is specified then any target that doesn't have an `PRODUCT_BUNDLE_IDENTIFIER` (via all levels of build settings) will get an autogenerated one by combining `bundleIdPrefix` and the target name: `bundleIdPrefix.name`. The target name will be stripped of all characters that aren't alphanumerics, hyphens, or periods. Underscores will be replace with hyphens.
- ⚪️ **settingPresets**: `String` - This controls the settings that are automatically applied to the project and its targets. These are the same build settings that Xcode would add when creating a new project. Project settings are applied by config type. Target settings are applied by the product type and platform. By default this is set to `all`
	- `all`: project and target settings
	- `project`: only project settings
	- `targets`: only target settings
	- `none`: no settings are automatically applied
- ⚪️ **developmentLanguage**: `String` - Sets the development language of the project. Defaults to `en`
- ⚪️ **usesTabs**: `Bool` - If this is specified, the Xcode project will override the user's setting determining whether or not tabs or spaces should be used in the project.
- ⚪️ **indentWidth**: `Int` - If this is specified, the Xcode project will override the user's setting for indent width in number of spaces.
- ⚪️ **tabWidth**: `Int` - If this is specified, the Xcode project will override the user's setting for indent width in number of spaces.

### Configs
Each config maps to a build type of either `debug` or `release` which will then apply default build settings to the project. Any value other than `debug` or `release` (for example `none`), will mean no default build settings will be applied to the project.

```yaml
configs:
  Debug: debug
  Release: release
```
If no configs are specified, default `Debug` and `Release` configs will be created automatically.


### Setting Groups
Setting groups are named groups of build settings that can be reused elsewhere. Each preset is a [Settings](#settings) schema, so can include other groups

```yaml
settingGroups:
  preset1:
    BUILD_SETTING: value
  preset2:
    base:
      BUILD_SETTING: value
    groups:
      - preset
  preset3:
     configs:
        debug:
        	groups:
            - preset
```

## Settings
Settings can either be a simple map of build settings `[String: String]`, or can be more advanced with the following properties:

- ⚪️ **groups**: `[String]` - List of setting groups to include and merge
- ⚪️ **configs**: [String: [Settings](#settings)] - Mapping of config name to a settings spec. These settings will only be applied for that config. Each key will be matched to any configs that contain the key and is case insensitive. So if you had `Staging Debug` and `Staging Release`, you could apply settings to both of them using `staging`.
- ⚪️ **base**: `[String: String]` - Used to specify default settings that apply to any config

```yaml
settings:
  BUILD_SETTING_1: value 1
  BUILD_SETTING_2: value 2
```

```yaml
settings:
  base:
    BUILD_SETTING_1: value 1
  configs:
    my_config:
      BUILD_SETTING_2: value 2
  groups:
    - my_settings
```

Settings are merged in the following order: groups, base, configs.

## Target

- 🔵 **type**: [Product Type](#product-type) - Product type of the target
- 🔵 **platform**: [Platform](#platform) - Platform of the target
- ⚪️ **sources**: [Sources](#sources) - Source directories of the target
- ⚪️ **configFiles**: [Config Files](#config-files) - `.xcconfig` files per config
- ⚪️ **settings**: [Settings](#settings) - Target specific build settings. Default platform and product type settings will be applied first before any custom settings defined here. Other context dependant settings will be set automatically as well:
	- `INFOPLIST_FILE`: If it doesn't exist your sources will be searched for `Info.plist` files and the first one found will be used for this setting
	- `FRAMEWORK_SEARCH_PATHS`: If carthage dependencies are used, the platform build path will be added to this setting
- ⚪️ **prebuildScripts**: [[Build Script](#build-script)] - Build scripts that run *before* any other build phases
- ⚪️ **postbuildScripts**: [[Build Script](#build-script)] - Build scripts that run *after* any other build phases
- ⚪️ **dependencies**: [[Dependency](#dependency)] - Dependencies for the target
- ⚪️ **scheme**: [Target Scheme](#target-scheme) - Generated scheme with tests or config variants
- ⚪️ **legacy**: [Legacy Target](#legacy-target) - When present, opt-in to make an Xcode "External Build System" legacy target instead.

### Product Type
This will provide default build settings for a certain product type. It can be any of the following:

- application
- framework
- library.dynamic
- library.static
- bundle
- bundle.unit-test
- bundle.ui-testing
- app-extension
- tool
- application.watchapp
- application.watchapp2
- watchkit-extension
- watchkit2-extension
- tv-app-extension
- application.messages
- app-extension.messages
- app-extension.messages-sticker-pack
- xpc-service
- "" (used for legacy targets)

### Platform
This will provide default build settings for a certain platform. It can be any of the following:

- iOS
- tvOS
- macOS
- watchOS

**Multi Platform targets**

You can also specify an array of platforms. This will generate a target for each platform.
If you reference the string `$platform` anywhere within the target spec, that will be replaced with the platform.

The generated targets by default will have a suffix of `_$platform` applied, you can change this by specifying a `platformSuffix` or `platformPrefix`.

If no `PRODUCT_NAME` build setting is specified for a target, this will be set to the target name, so that this target can be imported under a single name.

```yaml
targets:
  MyFramework:
    sources: MyFramework
    platform: [iOS, tvOS]
    type: framework
    settings:
      base:
        INFOPLIST_FILE: MyApp/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.myapp
        MY_SETTING: platform $platform
      groups:
        - $platform
```
The above will generate 2 targets named `MyFramework_iOS` and `MyFramework_tvOS`, with all the relevant platform build settings. They will both have a `PRODUCT_NAME` of `MyFramework`

### Sources
Specifies the source directories for a target. This can either be a single source or a list of sources. Applicable source files, resources, headers, and lproj files will be parsed appropriately.

A source can be provided via a string (the path) or an object of the form:

**Target Source Object**:

- 🔵 **path**: `String` - The path to the source file or directory.
- ⚪️ **name**: `String` - Can be used to override the name of the source file or directory. By default the last component of the path is used for the name
- ⚪️ **compilerFlags**: `[String]` or `String` - A list of compilerFlags to add to files under this specific path provided as a list or a space delimitted string. Defaults to empty.
- ⚪️ **type**: `String`: This can be one of the following values
	- `file`: a file reference with a parent group will be created (Default for files or directories with extensions)
	- `group`: a group with all it's containing files. (Default for directories without extensions)
	- `folder`: a folder reference.


```yaml
targets:
  MyTarget
    sources: MyTargetSource
  MyOtherTarget
    sources:
      - MyOtherTargetSource1
      - path: MyOtherTargetSource2
        name: MyNewName
        compilerFlags:
          - "-Werror"
          - "-Wextra"
      - path: MyOtherTargetSource3
        compilerFlags: "-Werror -Wextra"
      - path: Resources
        type: folder
```

### Dependency
A dependency can be one of a 3 types:

- `target: name` - links to another target
- `framework: path` - links to a framework
- `carthage: name` - helper for linking to a carthage framework

**Embed options**:

These only applied to `target` and `framework` dependencies.

- ⚪️ **embed**: `Bool` - Whether to embed the dependency. Defaults to true for application target and false for non application targets.
- ⚪️ **link**: `Bool` - Whether to link the dependency. Defaults to true but only static library and dynamic frameworks are linked. This only applies for target dependencies.
- ⚪️ **codeSign**: `Bool` - Whether the `codeSignOnCopy` setting is applied when embedding framework. Defaults to true
- ⚪️ **removeHeaders**: `Bool` - Whether the `removeHeadersOnCopy` setting is applied when embedding the framework. Defaults to true

**Implicit Framework options**:

This only applies to `framework` dependencies. Implicit framework dependencies are useful in Xcode Workspaces which have multiple `.xcodeproj` that are not embedded within each other yet have a dependency on a framework built in an adjacent `.xcodeproj`.  By having `Find Implicit Dependencies` checked within your scheme `Build Options` Xcode can link built frameworks in `BUILT_PRODUCTS_DIR`.

- ⚪️ **implicit**: `Bool` - Whether the framework is an implicit dependency. Defaults to `false` .

**Carthage Dependency**

Carthage frameworks are expected to be in `CARTHAGE_BUILD_PATH/PLATFORM/FRAMEWORK.framework` where:

 - `CARTHAGE_BUILD_PATH` = `options.carthageBuildPath` or `Carthage/Build` by default
 - `PLATFORM` = the target's platform
 - `FRAMEWORK` = the specified name.

If any applications contain carthage dependencies within itself or any dependent targets, a carthage copy files script is automatically added to the application containing all the relevant frameworks. A `FRAMEWORK_SEARCH_PATHS` setting is also automatically added

```yaml
targets:
  MyTarget:
    dependencies:
      - target: MyFramework
      - framework: path/to/framework.framework
      - carthage: Result
  MyFramework:
    type: framework
```

### Config Files
Specifies `.xcconfig` files for each configuration.

```yaml
targets:
  MyTarget:
    configFiles:
      Debug: config_files/debug.xcconfig
      Release: config_files/release.xcconfig
```

### Build Script
Run script build phases added via **prebuildScripts** or **postBuildScripts**. They run before or after any other build phases respectively and in the order defined. Each script can contain:

- 🔵 **path**: `String` - a relative or absolute path to a shell script
- 🔵 **script**: `String` - an inline shell script
- ⚪️ **name**: `String` - name of a script. Defaults to `Run Script`
- ⚪️ **inputFiles**: `[String]` - list of input files
- ⚪️ **outputFiles**: `[String]` - list of output files
- ⚪️ **shell**: `String` - shell used for the script. Defaults to `/bin/sh`
- ⚪️ **runOnlyWhenInstalling**: `Bool` - whether the script is only run when installing (runOnlyForDeploymentPostprocessing). Defaults to no

Either a **path** or **script** must be defined, the rest are optional.

A multiline script can be written using the various YAML multiline methods, for example with `|` as below:

```yaml
targets:
  MyTarget:
    prebuildScripts:
      - path: myscripts/my_script.sh
        name: My Script
        inputFiles:
          - $(SRCROOT)/file1
          - $(SRCROOT)/file2
        outputFiles:
          - $(DERIVED_FILE_DIR)/file1
          - $(DERIVED_FILE_DIR)/file2
    postbuildScripts:
      - script: swiftlint
        name: Swiftlint
      - script: |
      		command do
      		othercommand
```

###  Target Scheme
This is a convenience used to automatically generate schemes for a target based on different configs or included tests.

- 🔵 **configVariants**: `[String]` - This generates a scheme for each entry, using configs that contain the name with debug and release variants. This is useful for having different environment schemes.
- ⚪️ **testTargets**: `[String]` - a list of test targets that should be included in the scheme. These will be added to the build targets and the test entries
- ⚪️ **gatherCoverageData**: `Bool` - a boolean that indicates if this scheme should gather coverage data
- ⚪️ **commandLineArguments**: `[String:Bool]` - a dictionary from the argument name (`String`) to if it is enabled (`Bool`). These arguments will be added to the Test, Profile and Run scheme actions

For example, the spec below would create 3 schemes called:

- MyApp Test
- MyApp Staging
- MyApp Production

Each scheme would use different build configuration for the different build types, specifically debug configs for `run`, `test`, and `anaylze`, and release configs for `profile` and `archive`.
The MyUnitTests target would also be linked.

```
configs:
  Test Debug: debug
  Staging Debug: debug
  Production Debug: debug
  Test Release: release
  Staging Release: release
  Production Release: release
targets
  MyApp:
    scheme:
      testTargets:
        - MyUnitTests
      configVariants:
        - Test
        - Staging
        - Production
      gatherCoverageData: true
      commandLineArguments:
        "-MyEnabledArg": true
        "-MyDisabledArg": false
  MyUnitTests:
    sources: Tests
```

###  Legacy Target
By providing a legacy target, you are opting in to the "Legacy Target" mode. This is the "External Build Tool" from the Xcode GUI. This is useful for scripts that you want to run as dependencies of other targets, but you want to make sure that it only runs once even if it is specified as a dependency from multiple other targets.

- 🔵 **toolPath**: String - Path to the build tool used in the legacy target.
- ⚪️ **arguments**: String - Build arguments used for the build tool in the legacy target
- ⚪️ **passSettings**: Bool - Whether or not to pass build settings down to the build tool in the legacy target.
- ⚪️ **workingDirectory**: String - The working directory under which the build tool will be invoked in the legacy target.

