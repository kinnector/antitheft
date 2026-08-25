use std::os::raw::c_char;

extern "C" {
    pub fn initialize_telemetry_engine(
        bpf_obj_path: *const c_char,
        socket_path: *const c_char,
        auth_token: *const c_char,
    ) -> bool;

    pub fn start_telemetry_engine() -> bool;

    pub fn stop_telemetry_engine();

    /// Phase 6 (LINUX_COVERAGE_PLAN.md): `dev` (MetadataExt::dev()) makes the identity
    /// canonical across bind-mounts/multiple filesystems with overlapping inode ranges.
    pub fn add_sensitive_inode(dev: u64, inode: u64, category: u32) -> bool;
    /// Phase 3 (LINUX_COVERAGE_PLAN.md): register/unregister `owner_exec_inode` as a
    /// legitimate owner process for the protected resource `(resource_dev,
    /// resource_inode)`. Only takes effect once CONFIG_DEPLOYMENT_MODE == MODE_ANTITHEFT
    /// has been set (see run_agent's set_config_value(5, 2) call) -- otherwise the
    /// kernel side never consults it. `owner_exec_inode` stays a bare inode (Phase 6's
    /// dev+inode compositing applies to the protected resource identity, not this
    /// lossy owner-hash bucket input).
    pub fn add_resource_owner(resource_dev: u64, resource_inode: u64, owner_exec_inode: u64) -> bool;
    pub fn remove_resource_owner(resource_dev: u64, resource_inode: u64, owner_exec_inode: u64) -> bool;
    pub fn add_trusted_exec_inode(inode: u64, trust_level: u32) -> bool;
    /// Fix 10: query whether `inode` is present in the trusted_exec_inodes BPF map.
    /// Returns true if trusted, false if unknown/untrusted or BPF unavailable.
    pub fn is_trusted_exec_inode(inode: u64) -> bool;
    pub fn set_config_value(index: u32, value: u32) -> bool;
    pub fn update_process_threshold(pid: u32, start_time: u64, threshold: u32) -> bool;
    /// Phase 4 (LINUX_COVERAGE_PLAN.md): generic BpfMapType-indexed map write, used
    /// here to populate install_binary_map (map_type = 16) by resolved binary inode.
    pub fn update_map_entry(map_type: i32, pid: u32, start_time: u64, value: u32) -> bool;
    pub fn is_lsm_active() -> bool;
}
