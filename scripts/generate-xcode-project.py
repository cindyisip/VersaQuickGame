"""Generate a dependency-light Xcode project with deterministic object IDs."""
from pathlib import Path
import hashlib

root=Path(__file__).resolve().parents[1]
ios=root/'ios'
project=ios/'VersaQuickGame.xcodeproj'
project.mkdir(exist_ok=True)
def uid(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(s):return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
objects=[]
def add(name,body):
    identifier=uid(name);objects.append(f'\t\t{identifier} = {{ {body} }};');return identifier
files=[];sources=[];resources=[]
for p in sorted((ios/'VersaQuickGame').rglob('*.swift')):
    rel=p.relative_to(ios).as_posix()
    f=add('file:'+rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = "<group>";')
    files.append(f);sources.append(add('build:'+rel,f'isa = PBXBuildFile; fileRef = {f};'))
for rel,typ in [('VersaQuickGame/Assets.xcassets','folder.assetcatalog'),('VersaQuickGame/PrivacyInfo.xcprivacy','text.xml')]:
    f=add('file:'+rel,f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(rel)}; sourceTree = "<group>";')
    files.append(f);resources.append(add('build:'+rel,f'isa = PBXBuildFile; fileRef = {f};'))
config=add('base-config','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Base.xcconfig; sourceTree = "<group>";')
files.append(config)
product=add('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = VersaQuickGame.app; sourceTree = BUILT_PRODUCTS_DIR;')
products=add('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=add('main',f'isa = PBXGroup; children = ({",".join(files)},{products},); sourceTree = "<group>";')
package=add('supabase-package','isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/supabase/supabase-swift.git"; requirement = {kind = exactVersion; version = 2.55.2;};')
dep=add('supabase-product',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = Supabase;')
framework=add('supabase-build',f'isa = PBXBuildFile; productRef = {dep};')
sourcephase=add('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(sources)},); runOnlyForDeploymentPostprocessing = 0;')
resourcephase=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)},); runOnlyForDeploymentPostprocessing = 0;')
frameworkphase=add('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework},); runOnlyForDeploymentPostprocessing = 0;')
targetconfigs=[];projectconfigs=[]
for mode in ['Debug','Release']:
    settings={
      'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_ENTITLEMENTS':'VersaQuickGame/VersaQuickGame.entitlements',
      'CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'VersaQuickGame/Info.plist',
      'IPHONEOS_DEPLOYMENT_TARGET':'17.0','MARKETING_VERSION':'0.1.0',
      'PRODUCT_NAME':'$(TARGET_NAME)','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'1','SDKROOT':'iphoneos',
      'SWIFT_EMIT_LOC_STRINGS':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
      'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O',
      'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'
    }
    if mode=='Debug':settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
    body=' '.join(f'{k} = {q(v)};' for k,v in settings.items())
    targetconfigs.append(add('target-'+mode,f'isa = XCBuildConfiguration; baseConfigurationReference = {config}; buildSettings = {{ {body} }}; name = {mode};'))
    projectconfigs.append(add('project-'+mode,f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; }}; name = {mode};'))
targetlist=add('target-config-list',f'isa = XCConfigurationList; buildConfigurations = ({",".join(targetconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projectlist=add('project-config-list',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {targetlist}; buildPhases = ({sourcephase},{frameworkphase},{resourcephase},); buildRules = (); dependencies = (); name = VersaQuickGame; packageProductDependencies = ({dep},); productName = VersaQuickGame; productReference = {product}; productType = "com.apple.product-type.application";')
proj=add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1630; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.3; }}; }}; }}; buildConfigurationList = {projectlist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {main}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+proj+';\n}\n')
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
(schemes/'VersaQuickGame.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1630" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="VersaQuickGame.app" BlueprintName="VersaQuickGame" ReferencedContainer="container:VersaQuickGame.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="VersaQuickGame.app" BlueprintName="VersaQuickGame" ReferencedContainer="container:VersaQuickGame.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="VersaQuickGame.app" BlueprintName="VersaQuickGame" ReferencedContainer="container:VersaQuickGame.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
