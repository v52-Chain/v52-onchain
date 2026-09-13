// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title V52EvidenceRegistry
/// @notice Anchors the cryptographic commitment of a Vector52 `.v52` forensic
///         package on HashKey Chain (HSK). The registry stores only a hash of
///         the manifest, a hash of the methodology, a schema version, a
///         non-sensitive case identifier and the issuer address.
///
///         It NEVER stores the manifest itself, raw evidence, wallet
///         addresses under investigation, claims, verdicts or any other
///         personal or case-sensitive data. Anchoring proves *when* and *by
///         whom* a given `manifest_root` was committed on-chain; it proves
///         nothing about whether the underlying claim is true. Verification
///         of package integrity happens off-chain via `POST /v1/verify`
///         (SHA-256 comparison against the anchored `manifestRoot`).
///
/// @dev Deployed once per network. Only addresses explicitly allow-listed by
///      the contract owner (`issuers`) may call `anchorCase`. In the Vector52
///      backend this is the relayer wallet that sponsors gas for the anchor
///      operation after an x402 payment has settled — see
///      `v52-backend/app/services/hsk_anchor.py` and
///      `v52-onchain/README.md` for the full integration contract.
contract V52EvidenceRegistry {
    /// @notice One anchored commitment for a `.v52` package.
    struct Anchor {
        bytes32 manifestRoot;
        bytes32 methodologyHash;
        string schemaVersion;
        string caseId;
        address issuer;
        uint64 blockNumber;
        uint64 timestamp;
        bytes32 supersedes;
        bool exists;
    }

    /// @notice Contract owner. Can manage the issuer allow-list and transfer
    ///         ownership. Cannot anchor unless also allow-listed as an issuer.
    address public owner;

    /// @notice Addresses allowed to call `anchorCase`.
    mapping(address issuer => bool allowed) public issuers;

    /// @notice manifestRoot => full anchor record.
    mapping(bytes32 manifestRoot => Anchor anchor) public anchors;

    /// @notice caseId => manifestRoot of the most recently anchored version
    ///         for that case (updated on every `anchorCase` call, including
    ///         the very first one).
    mapping(string caseId => bytes32 manifestRoot) public latestManifestRootOf;

    /// @notice Total number of anchors ever recorded. Monotonically
    ///         increasing; useful for off-chain indexers as a sanity check.
    uint256 public anchorCount;

    event CaseAnchored(
        bytes32 indexed manifestRoot,
        address indexed issuer,
        string caseId,
        string schemaVersion,
        bytes32 methodologyHash,
        bytes32 supersedes,
        uint64 blockNumber,
        uint64 timestamp
    );

    event CaseSuperseded(
        bytes32 indexed oldManifestRoot, bytes32 indexed newManifestRoot, string caseId
    );

    event IssuerUpdated(address indexed issuer, bool allowed);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotIssuer();
    error ZeroAddress();
    error EmptyCaseId();
    error ZeroManifestRoot();
    error AlreadyAnchored(bytes32 manifestRoot);
    error UnknownSupersededManifestRoot(bytes32 manifestRoot);
    error SupersedesSelf();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyIssuer() {
        if (!issuers[msg.sender]) revert NotIssuer();
        _;
    }

    /// @param initialIssuer Optional address to allow-list at deploy time
    ///        (pass address(0) to skip and add issuers later via `setIssuer`).
    constructor(address initialIssuer) {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);

        if (initialIssuer != address(0)) {
            issuers[initialIssuer] = true;
            emit IssuerUpdated(initialIssuer, true);
        }
    }

    /// @notice Allow or revoke an address's permission to anchor cases.
    function setIssuer(address issuer, bool allowed) external onlyOwner {
        if (issuer == address(0)) revert ZeroAddress();
        issuers[issuer] = allowed;
        emit IssuerUpdated(issuer, allowed);
    }

    /// @notice Transfer contract ownership to a new address.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice Anchor a `.v52` package commitment on-chain.
    /// @param manifestRoot SHA-256 of the package's canonical `manifest.json`,
    ///        as `sha256(canonical_bytes)` truncated/interpreted as bytes32.
    /// @param methodologyHash Hash identifying the exact Contribution
    ///        Analysis / Claim Auditor methodology version used to produce
    ///        the package (e.g. keccak256 of "v52-contribution-0.1.0").
    /// @param schemaVersion Free-form `.v52` schema version string (e.g. "0.1.0").
    /// @param caseId Non-sensitive Vector52 case identifier (e.g.
    ///        "case_1_4a8b12f0_d8da6b_9f2a1b3c"). Never a wallet, claim or PII.
    /// @param supersedes manifestRoot of a prior anchor this one replaces, or
    ///        bytes32(0) if this is not a re-anchor.
    function anchorCase(
        bytes32 manifestRoot,
        bytes32 methodologyHash,
        string calldata schemaVersion,
        string calldata caseId,
        bytes32 supersedes
    ) external onlyIssuer {
        if (manifestRoot == bytes32(0)) revert ZeroManifestRoot();
        if (bytes(caseId).length == 0) revert EmptyCaseId();
        if (anchors[manifestRoot].exists) revert AlreadyAnchored(manifestRoot);
        if (supersedes == manifestRoot) revert SupersedesSelf();
        if (supersedes != bytes32(0) && !anchors[supersedes].exists) {
            revert UnknownSupersededManifestRoot(supersedes);
        }

        uint64 blockNumber = uint64(block.number);
        uint64 timestamp = uint64(block.timestamp);

        anchors[manifestRoot] = Anchor({
            manifestRoot: manifestRoot,
            methodologyHash: methodologyHash,
            schemaVersion: schemaVersion,
            caseId: caseId,
            issuer: msg.sender,
            blockNumber: blockNumber,
            timestamp: timestamp,
            supersedes: supersedes,
            exists: true
        });

        latestManifestRootOf[caseId] = manifestRoot;
        unchecked {
            anchorCount += 1;
        }

        emit CaseAnchored(
            manifestRoot,
            msg.sender,
            caseId,
            schemaVersion,
            methodologyHash,
            supersedes,
            blockNumber,
            timestamp
        );

        if (supersedes != bytes32(0)) {
            emit CaseSuperseded(supersedes, manifestRoot, caseId);
        }
    }

    /// @notice Return the full anchor record for a manifest root.
    function getAnchor(bytes32 manifestRoot) external view returns (Anchor memory) {
        return anchors[manifestRoot];
    }

    /// @notice Whether a given manifest root has been anchored.
    function isAnchored(bytes32 manifestRoot) external view returns (bool) {
        return anchors[manifestRoot].exists;
    }

    /// @notice Convenience getter mirroring `latestManifestRootOf` for callers
    ///         that prefer an explicit function over the public mapping.
    function getLatestManifestRoot(string calldata caseId) external view returns (bytes32) {
        return latestManifestRootOf[caseId];
    }
}
