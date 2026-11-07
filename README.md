Moj nvim-dap-view native Beads recovery, 2026-11-07

Contains the full quiescent live .beads/embeddeddolt/dv database including Dolt history, the existing native .beads/backup with its recorded commit, metadata/config, and 50 issues plus one memory. Source files and Git indexes were unchanged.

Verify with sha256sum -c SHA256SUMS. Extract only into a new empty recovery directory: mkdir recovered-moj && tar -xzf moj-beads-native-20261107.tar.gz -C recovered-moj

Do not restore over an existing database. The archived config retains historical remote settings; inspect before invoking mutating commands. No backup init/sync or canonical reconciliation was performed.

Fingerprint algorithm: SHA256 of sorted relative-path + NUL + file-SHA256 + newline, for every file below the indicated root. snapshot-manifest.json includes individual hashes and head checks.
