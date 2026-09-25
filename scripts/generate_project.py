"""Generate the dependency-free Xcode project. Run with Python 3."""
import hashlib
import json
import pathlib
import plistlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
objects = {}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def obj(key, **fields):
    ident = uid(key); objects[ident] = fields; return ident

def config_list(key, settings):
    configs = []
    for name in ['Debug', 'Release']:
        values = dict(settings)
        values['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if name == 'Debug' else '-O'
        configs.append(obj(key + name, isa='XCBuildConfiguration', buildSettings=values, name=name))
    return obj(key + 'Configs', isa='XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

shared = sorted(ROOT.glob('Sources/DepartureCore/*.swift')) + sorted(ROOT.glob('Apps/Shared/*.swift'))
refs = []
products = []
targets = []
for kind, name, bundle, platform, version, family in [('iOS', 'RutgersDeparture', 'edu.example.RutgersDeparture', 'iphoneos', '17.0', '1,2'), ('Watch', 'RutgersDepartureWatch', 'edu.example.RutgersDeparture.watchkitapp', 'watchos', '10.0', '4')]:
    files = shared + sorted((ROOT / 'Apps' / kind).glob('*.swift'))
    builds = []
    for path in files:
        rel = str(path.relative_to(ROOT))
        ref = obj(rel, isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=rel, sourceTree='<group>')
        if ref not in refs: refs.append(ref)
        builds.append(obj(kind + rel, isa='PBXBuildFile', fileRef=ref))
    product = obj(kind + 'Product', isa='PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0, path=name+'.app', sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    source_phase = obj(kind+'Sources', isa='PBXSourcesBuildPhase', buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
    framework_phase = obj(kind+'Frameworks', isa='PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    settings = {'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'SDKROOT': platform,
                'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator' if kind == 'iOS' else 'watchos watchsimulator',
                'TARGETED_DEVICE_FAMILY': family, 'SWIFT_VERSION': '5.0', 'CODE_SIGN_STYLE': 'Automatic',
                'INFOPLIST_FILE': f'Apps/{kind}/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO', 'MARKETING_VERSION': '1.0',
                'CURRENT_PROJECT_VERSION': '1', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
                'IPHONEOS_DEPLOYMENT_TARGET' if kind == 'iOS' else 'WATCHOS_DEPLOYMENT_TARGET': version}
    if kind == 'Watch': settings['SKIP_INSTALL'] = 'YES'
    target = obj(kind+'Target', isa='PBXNativeTarget', buildConfigurationList=config_list(kind, settings), buildPhases=[source_phase, framework_phase], buildRules=[], dependencies=[], name=name, productName=name, productReference=product, productType='com.apple.product-type.application')
    targets.append(target)
    info = {'CFBundleDevelopmentRegion': 'en', 'CFBundleDisplayName': 'Rutgers Departure', 'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': '$(PRODUCT_NAME)', 'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)'}
    if kind == 'iOS':
        info.update({'LSRequiresIPhoneOS': True, 'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'], 'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}, 'NSLocalNetworkUsageDescription': 'Connect to your development transit server to load bus predictions.'})
    else: info.update({'WKApplication': True, 'WKCompanionAppBundleIdentifier': 'edu.example.RutgersDeparture', 'WKRunsIndependentlyOfCompanionApp': False})
    (ROOT / 'Apps' / kind / 'Info.plist').write_bytes(plistlib.dumps(info))

proxy = obj('WatchProxy', isa='PBXContainerItemProxy', containerPortal=uid('Project'), proxyType=1, remoteGlobalIDString=targets[1], remoteInfo='RutgersDepartureWatch')
dependency = obj('WatchDependency', isa='PBXTargetDependency', target=targets[1], targetProxy=proxy)
embed_file = obj('WatchEmbedFile', isa='PBXBuildFile', fileRef=products[1], settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
embed = obj('EmbedWatch', isa='PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='$(CONTENTS_FOLDER_PATH)/Watch', dstSubfolderSpec=16, files=[embed_file], name='Embed Watch Content', runOnlyForDeploymentPostprocessing=0)
objects[targets[0]]['dependencies'] = [dependency]
objects[targets[0]]['buildPhases'].append(embed)
product_group = obj('Products', isa='PBXGroup', children=products, name='Products', sourceTree='<group>')
group = obj('Main', isa='PBXGroup', children=refs+[product_group], sourceTree='<group>')
project = obj('Project', isa='PBXProject', attributes={'LastUpgradeCheck': '1600', 'BuildIndependentTargetsInParallel': 'YES'}, buildConfigurationList=config_list('Project', {'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '5.0'}), compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0, knownRegions=['en','Base'], mainGroup=group, productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets)
def render(value):
    if isinstance(value, dict): return '{\n' + '\n'.join(f'{json.dumps(k)} = {render(v)};' for k, v in value.items()) + '\n}'
    if isinstance(value, list): return '(' + ', '.join(render(v) for v in value) + ')'
    return str(value) if isinstance(value,int) else json.dumps(value)
folder = ROOT / 'RutgersDeparture.xcodeproj'
folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion': 1,'classes': {},'objectVersion': 56,'objects': objects,'rootObject': project}))
schemes = folder/'xcshareddata'/'xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
for kind, name in [('iOS', 'RutgersDeparture'), ('Watch', 'RutgersDepartureWatch')]:
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(kind+"Target")}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:RutgersDeparture.xcodeproj"/>'
    (schemes/(name+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated RutgersDeparture.xcodeproj')
