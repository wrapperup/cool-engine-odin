package livepp

foreign import livepp_api { "windows/LivePP_API.lib" }

PP_PLATFORM_LIBRARY_PREFIX_ANSI :: "";

LPP_PLATFORM_LIBRARY_NAME_ANSI :: "\\Agent\\x64\\LPP_Agent_x64_CPP.dll";

LPP_MAX_PATH :: 260;

LPP_VERSION :: "2.8.1";

LPP_PRECOMPILE_HOOK_SECTION :: ".lpp_precompile_hooks";
LPP_POSTCOMPILE_HOOK_SECTION :: ".lpp_postcompile_hooks";

LPP_COMPILE_START_HOOK_SECTION :: ".lpp_compile_start_hooks";
LPP_COMPILE_SUCCESS_HOOK_SECTION :: ".lpp_compile_success_hooks";
LPP_COMPILE_ERROR_HOOK_SECTION :: ".lpp_compile_error_hooks";

LPP_LINK_START_HOOK_SECTION :: ".lpp_link_start_hooks";
LPP_LINK_SUCCESS_HOOK_SECTION :: ".lpp_link_success_hooks";
LPP_LINK_ERROR_HOOK_SECTION :: ".lpp_link_error_hooks";

LPP_HOTRELOAD_PREPATCH_HOOK_SECTION :: ".lpp_hotreload_prepatch_hooks";
LPP_HOTRELOAD_POSTPATCH_HOOK_SECTION :: ".lpp_hotreload_postpatch_hooks";

LPP_GLOBAL_HOTRELOAD_START_HOOK_SECTION :: ".lpp_global_hotreload_start_hooks";
LPP_GLOBAL_HOTRELOAD_END_HOOK_SECTION :: ".lpp_global_hotreload_end_hooks";

// opaque types
HINSTANCE__ :: struct {}
HINSTANCE :: ^HINSTANCE__;
HMODULE :: HINSTANCE;
IMAGE_DOS_HEADER :: struct {}

// standard types
BOOL :: i32;

// Type of a Live++ agent module.
LppAgentModule :: HMODULE;

// Linker pseudo-variable representing the DOS header of the module we're being compiled into.
// See Raymond Chen's blog ("Accessing the current module's HINSTANCE from a static library"):
// https://blogs.msdn.microsoft.com/oldnewthing/20041025-00/?p=37483
__ImageBase: IMAGE_DOS_HEADER;

// ------------------------------------------------------------------------------------------------
// WINDOWS-SPECIFIC API
// ------------------------------------------------------------------------------------------------

// Define ID types to uniquely identify hook function signatures.
LppPrecompileHookId :: struct {
    unused: u8,
}
LppPostcompileHookId :: struct {
    unused: u8,
}

LppCompileStartHookId :: struct {
    unused: u8,
}
LppCompileSuccessHookId :: struct {
    unused: u8,
}
LppCompileErrorHookId :: struct {
    unused: u8,
}

LppLinkStartHookId :: struct {
    unused: u8,
}
LppLinkSuccessHookId :: struct {
    unused: u8,
}
LppLinkErrorHookId :: struct {
    unused: u8,
}

LppHotReloadPrepatchHookId :: struct {
    unused: u8,
}
LppHotReloadPostpatchHookId :: struct {
    unused: u8,
}

LppGlobalHotReloadStartHookId :: struct {
    unused: u8,
}
LppGlobalHotReloadEndHookId :: struct {
    unused: u8,
}

// ------------------------------------------------------------------------------------------------
// API STATUS & OPTIONS
// ------------------------------------------------------------------------------------------------
LppConnectionStatus :: enum i32 {
    SUCCESS                 = 0,
    FAILURE                 = 1,
    UNEXPECTED_VERSION_BLOB = 2,
    VERSION_MISMATCH        = 3,
}

LppModulesOption :: enum i32 {
    NONE               = 0,
    ALL_IMPORT_MODULES = 1,
}

LppReloadOption :: enum i32 {
    SYNCHRONIZE_WITH_COMPILATION_AND_RELOAD = 0,
    SYNCHRONIZE_WITH_RELOAD                 = 1,
}

LppReloadBehaviour :: enum i32 {
    CONTINUE_EXECUTION             = 0,
    WAIT_UNTIL_CHANGES_ARE_APPLIED = 1,
}

LppRestartOption :: enum i32 {
    CURRENT_PROCESS = 0,
    ALL_PROCESSES   = 1,
}

LppRestartBehaviour :: enum i32 {
    DEFAULT_EXIT        = 0,
    EXIT_WITH_FLUSH     = 1,
    EXIT_WITHOUT_FLUSH  = 2,
    INSTANT_TERMINATION = 3,
}

// Enum identifying different output type masks.
LppLocalPreferencesLoggingTypeMask :: enum i32 {
    NONE    = 0,
    SUCCESS = 1,
    INFO    = 2,
    WARNING = 4,
    ERROR   = 8,
    PANIC   = 16,
    ALL     = 255,
}

Logging :: struct {
    // A type mask that specifies which types of messages should be logged natively, e.g. to the Visual Studio output window using OutputDebugString.
    // Valid values are any combination of LppLocalPreferencesLoggingTypeMask enumerator values.
    nativeTypeMask: u32,
}

// Struct defining local preferences to use when creating an agent.
// These preferences must be defined at the time of agent creation and cannot be stored in the global or project preferences.
// They can only be set using the corresponding API/function argument and must be created by calling LppCreateDefaultLocalPreferences().
LppLocalPreferences :: struct {
    logging: Logging,
}

General :: struct {
    spawnBrokerForLocalConnection:     bool,
    showErrorOnFailedBrokerConnection: bool,
    directoryToBroker:                 ^i16, // directory to the Broker, either relative to the Agent/Bridge, or absolute
}

PreBuild :: struct {
    isEnabled:          bool,
    executable:         ^i16,
    workingDirectory:   ^i16,
    commandLineOptions: ^u8,
}

HotReload :: struct {
    objectFileExtensions:                 ^u8,
    libraryFileExtensions:                ^u8,
    sourcePathFilters:                    ^u8,
    captureToolchainEnvironmentTimeout:   i32,

    preBuild:                             PreBuild,

    callCompileHooksForHaltedProcesses:   bool,
    callLinkHooksForHaltedProcesses:      bool,
    callHotReloadHooksForHaltedProcesses: bool,
}

Compiler :: struct {
    overrideLocation:           ^i16, // isOverridden must be set to true
    commandLineOptions:         ^u8,
    captureEnvironment:         bool,
    isOverridden:               bool,
    useOverrideAsFallback:      bool, // isOverridden must be set to true
    forcePrecompiledHeaderPDBs: bool,
    removeShowIncludes:         bool,
    removeSourceDependencies:   bool,
}

Linker :: struct {
    overrideLocation:                ^i16, // isOverridden must be set to true
    commandLineOptions:              ^u8,
    captureEnvironment:              bool,
    isOverridden:                    bool,
    useOverrideAsFallback:           bool, // isOverridden must be set to true
    suppressCreationOfImportLibrary: bool,
}

ExceptionHandler :: struct {
    isEnabled: bool,
    order:     i32, // 0 = last, 1 = first
}

    ContinuousCompilation :: struct {
        directory: ^i16,
        timeout:   i32,
        isEnabled: bool,
    }

    VirtualDrive :: struct {
        letterPlusColon: ^u8,
        directory:       ^i16,
        isEnabled:       bool,
    }

    UnitySplitting :: struct {
        fileExtensions: ^u8,
        threshold:      i32,
        isEnabled:      bool,
    }


// Struct defining project preferences.
// They can only be set using the corresponding API/function argument and must be created by calling LppCreateDefaultProjectPreferences().
LppProjectPreferences :: struct {
    general:               General,
    hotReload:             HotReload,
    compiler:              Compiler,
    linker:                Linker,
    exceptionHandler:      ExceptionHandler,
    continuousCompilation: ContinuousCompilation,
    virtualDrive:          VirtualDrive,
    unitySplitting:        UnitySplitting,
}

// ------------------------------------------------------------------------------------------------
// PREFERENCES API
// ------------------------------------------------------------------------------------------------
LppBoolPreferences :: enum i32 {
    LOGGING_PRINT_TIMESTAMPS              = 0,
    LOGGING_ENABLE_WORDWRAP               = 1,
    NOTIFICATIONS_ENABLED                 = 2,
    NOTIFICATIONS_PLAY_SOUND_ON_SUCCESS   = 3,
    NOTIFICATIONS_PLAY_SOUND_ON_ERROR     = 4,
    HOT_RELOAD_LOAD_INCOMPLETE_MODULES    = 5,
    HOT_RELOAD_LOAD_INCOMPLETE_COMPILANDS = 6,
    HOT_RELOAD_DELETE_PATCH_FILES         = 7,
    HOT_RELOAD_CLEAR_LOG                  = 8,
    VISUAL_STUDIO_SHOW_MODAL_DIALOG       = 9,
}

LppIntPreferences :: enum i32 {
    HOT_RELOAD_TIMEOUT       = 0,
    HOT_RESTART_TIMEOUT      = 1,

    UI_STYLE                 = 2,

    LOGGING_VERBOSITY        = 3,

    NOTIFICATIONS_FOCUS_TYPE = 4,
}

LppStringPreferences :: enum i32 {
    LOGGING_FONT                        = 0,
    NOTIFICATIONS_SOUND_ON_SUCCESS_PATH = 1,
    NOTIFICATIONS_SOUND_ON_ERROR_PATH   = 2,
}

LppShortcutPreferences :: enum i32 {
    HOT_RELOAD               = 0,
    HOT_RESTART              = 1,
    IDE_TOGGLE_OPTIMIZATIONS = 2,
}

// Returns whether a module should be loaded.
LppFilterFunctionANSI :: #type proc "c" (_context: rawptr, path: ^u8) -> bool 

// Returns whether a module should be loaded.
LppFilterFunction :: #type proc "c" (_context: rawptr, path: ^i16) -> bool 

// Connection callback function type.
LppOnConnectionCallback :: #type proc "c" (_context: rawptr, status: LppConnectionStatus) 
LppOnConnectionFunction :: #type proc "c" (_context: rawptr, callback: LppOnConnectionCallback) 

LppLogMessageFunctionANSI :: #type proc "c" (message: ^u8) 
LppLogMessageFunction :: #type proc "c" (message: ^i16) 

LppEnableAutomaticHandlingOfDynamicallyLoadedModulesFunctionANSI :: #type proc "c" (callbackContext: rawptr, callback: LppFilterFunctionANSI) 
LppEnableAutomaticHandlingOfDynamicallyLoadedModulesFunction :: #type proc "c" (callbackContext: rawptr, callback: LppFilterFunction) 

LppEnableModuleFunctionANSI :: #type proc "c" (relativeOrFullPath: ^u8, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunctionANSI) 
LppEnableModuleFunction :: #type proc "c" (relativeOrFullPath: ^i16, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunction) 

LppEnableModulesFunctionANSI :: #type proc "c" (arrayOfRelativeOrFullPaths: ^^u8, count: u64, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunctionANSI) 
LppEnableModulesFunction :: #type proc "c" (arrayOfRelativeOrFullPaths: ^^i16, count: u64, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunction) 

LppDisableModuleFunctionANSI :: #type proc "c" (relativeOrFullPath: ^u8, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunctionANSI) 
LppDisableModuleFunction :: #type proc "c" (relativeOrFullPath: ^i16, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunction) 

LppDisableModulesFunctionANSI :: #type proc "c" (arrayOfRelativeOrFullPaths: ^^u8, count: u64, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunctionANSI) 
LppDisableModulesFunction :: #type proc "c" (arrayOfRelativeOrFullPaths: ^^i16, count: u64, options: LppModulesOption, callbackContext: rawptr, callback: LppFilterFunction) 

LppWantsReloadFunction :: #type proc "c" (option: LppReloadOption) -> bool 
LppScheduleReloadFunction :: #type proc "c" () 
LppReloadFunction :: #type proc "c" (behaviour: LppReloadBehaviour) 

LppWantsRestartFunction :: #type proc "c" () -> bool 
LppScheduleRestartFunction :: #type proc "c" (option: LppRestartOption) 
LppRestartFunction :: #type proc "c" (behaviour: LppRestartBehaviour, exitCode: u32, commandLineArguments: ^i16) 

LppSetBoolPreferencesFunction :: #type proc "c" (preferences: LppBoolPreferences, value: bool) 
LppSetIntPreferencesFunction :: #type proc "c" (preferences: LppIntPreferences, value: i32) 
LppSetStringPreferencesFunction :: #type proc "c" (preferences: LppStringPreferences, value: ^u8) 
LppSetShortcutPreferencesFunction :: #type proc "c" (preferences: LppShortcutPreferences, virtualKeyCode: i32, modifiers: i32) 

// ------------------------------------------------------------------------------------------------
// API AGENTS
// ------------------------------------------------------------------------------------------------
LppDefaultAgent :: struct {
    // Internal platform-specific module. DO NOT USE!
    internalModuleDoNotUse:                                LppAgentModule,

    // Calls the given callback with a user-supplied context and internal connection status after an attempt has been made to connect the Agent to the Bridge/Broker.
    OnConnection:                                          LppOnConnectionFunction,

    // Logs a message to the Live++ UI.
    LogMessageANSI:                                        LppLogMessageFunctionANSI,
    LogMessage:                                            LppLogMessageFunction,

    // Enables automatic handling of dynamically loaded modules (e.g. loaded via LoadLibrary()).
    // Those modules will be automatically enabled during load, and disabled during unload.
    EnableAutomaticHandlingOfDynamicallyLoadedModulesANSI: LppEnableAutomaticHandlingOfDynamicallyLoadedModulesFunctionANSI,
    EnableAutomaticHandlingOfDynamicallyLoadedModules:     LppEnableAutomaticHandlingOfDynamicallyLoadedModulesFunction,

    // Enables a module with the given options.
    EnableModuleANSI:                                      LppEnableModuleFunctionANSI,
    EnableModule:                                          LppEnableModuleFunction,

    // Enables several modules with the given options.
    EnableModulesANSI:                                     LppEnableModulesFunctionANSI,
    EnableModules:                                         LppEnableModulesFunction,

    // Disables a module with the given options.
    DisableModuleANSI:                                     LppDisableModuleFunctionANSI,
    DisableModule:                                         LppDisableModuleFunction,

    // Disables several modules with the given options.
    DisableModulesANSI:                                    LppDisableModulesFunctionANSI,
    DisableModules:                                        LppDisableModulesFunction,

    // Schedules a hot-reload operation.
    ScheduleReload:                                        LppScheduleReloadFunction,

    // Schedules a hot-restart operation.
    ScheduleRestart:                                       LppScheduleRestartFunction,

    // Sets a boolean preference to the given value.
    SetBoolPreferences:                                    LppSetBoolPreferencesFunction,

    // Sets an integer preference to the given value.
    SetIntPreferences:                                     LppSetIntPreferencesFunction,

    // Sets a string preference to the given value.
    SetStringPreferences:                                  LppSetStringPreferencesFunction,

    // Sets a shortcut preference to the given value.
    // Modifiers can be any combination of MOD_ALT, MOD_CONTROL, MOD_SHIFT and MOD_WIN, e.g. MOD_ALT | MOD_CONTROL.
    SetShortcutPreferences:                                LppSetShortcutPreferencesFunction,
}

LppSynchronizedAgent :: struct {
    // Internal platform-specific module. DO NOT USE!
    internalModuleDoNotUse:                                LppAgentModule,

    // Calls the given callback with a user-supplied context and internal connection status after an attempt has been made to connect the Agent to the Bridge/Broker.
    OnConnection:                                          LppOnConnectionFunction,

    // Logs a message to the Live++ UI.
    LogMessageANSI:                                        LppLogMessageFunctionANSI,
    LogMessage:                                            LppLogMessageFunction,

    // Enables automatic handling of dynamically loaded modules (e.g. loaded via LoadLibrary()).
    // Those modules will be automatically enabled during load, and disabled during unload.
    EnableAutomaticHandlingOfDynamicallyLoadedModulesANSI: LppEnableAutomaticHandlingOfDynamicallyLoadedModulesFunctionANSI,
    EnableAutomaticHandlingOfDynamicallyLoadedModules:     LppEnableAutomaticHandlingOfDynamicallyLoadedModulesFunction,

    // Enables a module with the given options.
    EnableModuleANSI:                                      LppEnableModuleFunctionANSI,
    EnableModule:                                          LppEnableModuleFunction,

    // Enables several modules with the given options.
    EnableModulesANSI:                                     LppEnableModulesFunctionANSI,
    EnableModules:                                         LppEnableModulesFunction,

    // Disables a module with the given options.
    DisableModuleANSI:                                     LppDisableModuleFunctionANSI,
    DisableModule:                                         LppDisableModuleFunction,

    // Disables several modules with the given options.
    DisableModulesANSI:                                    LppDisableModulesFunctionANSI,
    DisableModules:                                        LppDisableModulesFunction,

    // Returns whether Live++ wants to hot-reload modified files.
    // Returns true once the shortcut has been pressed, or modified files have been detected when continuous compilation is enabled.
    WantsReload:                                           LppWantsReloadFunction,

    // Schedules a hot-reload operation, making WantsReload() return true as soon as possible.
    ScheduleReload:                                        LppScheduleReloadFunction,

    // Instructs Live++ to reload all changes, respecting the given behaviour.
    Reload:                                                LppReloadFunction,

    // Returns whether Live++ wants to hot-restart the process.
    // Returns true once the process has been selected for hot-restart in the Live++ UI, or a manual restart was scheduled.
    WantsRestart:                                          LppWantsRestartFunction,

    // Schedules a hot-restart operation, making WantsRestart() return true as soon as possible.
    ScheduleRestart:                                       LppScheduleRestartFunction,

    // Restarts the process, respecting the given behaviour.
    // Does not return.
    Restart:                                               LppRestartFunction,

    // Sets a boolean preference to the given value.
    SetBoolPreferences:                                    LppSetBoolPreferencesFunction,

    // Sets an integer preference to the given value.
    SetIntPreferences:                                     LppSetIntPreferencesFunction,

    // Sets a string preference to the given value.
    SetStringPreferences:                                  LppSetStringPreferencesFunction,

    // Sets a shortcut preference to the given value.
    // Modifiers can be any combination of MOD_ALT, MOD_CONTROL, MOD_SHIFT and MOD_WIN, e.g. MOD_ALT | MOD_CONTROL.
    SetShortcutPreferences:                                LppSetShortcutPreferencesFunction,
}

@(default_calling_convention="c", link_prefix="Lpp")
foreign livepp_api {
    HelperMakeLibraryNameANSI :: proc(prefix: cstring, pathWithoutTrailingSlash: cstring, libraryName: cstring, output: ^u8, outputSize: u64) ---

    HelperMakeLibraryName :: proc(prefix: ^i16, pathWithoutTrailingSlash: ^i16, libraryName: ^i16, output: ^i16, outputSize: u64) ---

    PlatformLoadLibraryANSI :: proc(name: cstring) -> HMODULE ---

    PlatformLoadLibrary :: proc(name: ^i16) -> HMODULE ---

    PlatformUnloadLibrary :: proc(module: HMODULE) ---

    PlatformGetFunctionAddress :: proc(module: HMODULE, name: cstring) -> rawptr ---

    PlatformGetCurrentModulePathANSI :: proc() -> cstring ---

    PlatformGetCurrentModulePath :: proc() -> ^i16 ---

    // Creates default-initialized local preferences.
    CreateDefaultLocalPreferences :: proc() -> LppLocalPreferences ---

    // Creates default-initialized project preferences.
    CreateDefaultProjectPreferences :: proc() -> LppProjectPreferences ---

    // Loads the agent from a shared library.
    InternalLoadAgentLibraryANSI :: proc(absoluteOrRelativePathWithoutTrailingSlash: cstring) -> LppAgentModule ---

    // Loads the agent from a shared library.
    InternalLoadAgentLibrary :: proc(absoluteOrRelativePathWithoutTrailingSlash: ^i16) -> LppAgentModule ---

    // Checks whether the agent version and API version match.
    InternalCheckVersion :: proc(lppModule: LppAgentModule) ---

    // Creates a default agent, either loading the project preferences from a file, or passing them along.
    InternalCreateDefaultAgentANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring, absoluteOrRelativePathToProjectPreferences: cstring, projectPreferences: ^LppProjectPreferences) -> LppDefaultAgent ---

    // Creates a default agent, either loading the project preferences from a file, or passing them along.
    InternalCreateDefaultAgent :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16, absoluteOrRelativePathToProjectPreferences: ^i16, projectPreferences: ^LppProjectPreferences) -> LppDefaultAgent ---

    // Creates a synchronized agent, either loading the project preferences from a file, or passing them along.
    InternalCreateSynchronizedAgentANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring, absoluteOrRelativePathToProjectPreferences: cstring, projectPreferences: ^LppProjectPreferences) -> LppSynchronizedAgent ---

    // Creates a synchronized agent, either loading the project preferences from a file, or passing them along.
    InternalCreateSynchronizedAgent :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16, absoluteOrRelativePathToProjectPreferences: ^i16, projectPreferences: ^LppProjectPreferences) -> LppSynchronizedAgent ---

    // Destroys the given agent.
    InternalDestroyAgent :: proc(agentModule: LppAgentModule) --- 

    // Returns the fully qualified path of the current module, e.g. "C:\MyDirectory\MyApplication.exe".
    GetCurrentModulePathANSI :: proc() -> cstring ---

    // Returns the fully qualified path of the current module, e.g. "C:\MyDirectory\MyApplication.exe".
    GetCurrentModulePath :: proc() -> ^i16 ---

    // Returns whether the given default agent is valid.
    IsValidDefaultAgent :: proc(agent: ^LppDefaultAgent) -> bool ---

    // Creates a default agent, loading the Live++ agent from the given path, e.g. "ThirdParty\LivePP".
    CreateDefaultAgentANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring) -> LppDefaultAgent ---

    // Creates a default agent, loading the Live++ agent from the given path, e.g. "ThirdParty\LivePP".
    CreateDefaultAgent :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16) -> LppDefaultAgent ---

    // Creates a default agent with the given project preferences.
    CreateDefaultAgentWithPreferencesANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring, projectPreferences: ^LppProjectPreferences) -> LppDefaultAgent ---

    // Creates a default agent with the given project preferences.
    CreateDefaultAgentWithPreferences :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16, projectPreferences: ^LppProjectPreferences) -> LppDefaultAgent ---

    // Creates a default agent, loading project preferences from the given path.
    CreateDefaultAgentWithPreferencesFromFileANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring, absoluteOrRelativePathToProjectPreferences: cstring) -> LppDefaultAgent ---

    // Creates a default agent, loading project preferences from the given path.
    CreateDefaultAgentWithPreferencesFromFile :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16, absoluteOrRelativePathToProjectPreferences: ^i16) -> LppDefaultAgent ---

    // Destroys the given default agent.
    DestroyDefaultAgent :: proc(agent: ^LppDefaultAgent) ---

    // Returns whether the given synchronized agent is valid.
    IsValidSynchronizedAgent :: proc(agent: ^LppSynchronizedAgent) -> bool ---

    // Creates a synchronized agent, loading the Live++ agent from the given path, e.g. "ThirdParty\LivePP".
    CreateSynchronizedAgentANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring) -> LppSynchronizedAgent ---

    // Creates a synchronized agent, loading the Live++ agent from the given path, e.g. "ThirdParty\LivePP".
    CreateSynchronizedAgent :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16) -> LppSynchronizedAgent ---

    // Creates a synchronized agent with the given project preferences.
    CreateSynchronizedAgentWithPreferencesANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring, projectPreferences: ^LppProjectPreferences) -> LppSynchronizedAgent ---

    // Creates a synchronized agent with the given project preferences.
    CreateSynchronizedAgentWithPreferences :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16, projectPreferences: ^LppProjectPreferences) -> LppSynchronizedAgent ---

    // Creates a synchronized agent, loading project preferences from the given path.
    CreateSynchronizedAgentWithPreferencesFromFileANSI :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: cstring, absoluteOrRelativePathToProjectPreferences: cstring) -> LppSynchronizedAgent ---

    // Creates a synchronized agent, loading project preferences from the given path.
    CreateSynchronizedAgentWithPreferencesFromFile :: proc(localPreferences: ^LppLocalPreferences, absoluteOrRelativePathWithoutTrailingSlash: ^i16, absoluteOrRelativePathToProjectPreferences: ^i16) -> LppSynchronizedAgent ---

    // Destroys the given synchronized agent.
    DestroySynchronizedAgent :: proc(agent: ^LppSynchronizedAgent) ---
}
