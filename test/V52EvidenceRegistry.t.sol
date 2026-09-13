// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {V52EvidenceRegistry} from "../contracts/hsk/V52EvidenceRegistry.sol";

contract V52EvidenceRegistryTest is Test {
    V52EvidenceRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal issuer = makeAddr("issuer");
    address internal otherIssuer = makeAddr("otherIssuer");
    address internal stranger = makeAddr("stranger");

    bytes32 internal constant ROOT_A = keccak256("manifest-a");
    bytes32 internal constant ROOT_B = keccak256("manifest-b");
    bytes32 internal constant METHOD_HASH = keccak256("v52-contribution-0.1.0");
    string internal constant SCHEMA = "0.1.0";
    string internal constant CASE_ID = "case_1_4a8b12f0_d8da6b_9f2a1b3c";

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

    function setUp() public {
        vm.prank(owner);
        registry = new V52EvidenceRegistry(issuer);
    }

    // ─────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────

    function test_constructor_setsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_constructor_allowlistsInitialIssuer() public view {
        assertTrue(registry.issuers(issuer));
    }

    function test_constructor_emitsOwnershipTransferred() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(0), owner);
        vm.prank(owner);
        new V52EvidenceRegistry(issuer);
    }

    function test_constructor_withZeroInitialIssuer_setsNoIssuer() public {
        vm.prank(owner);
        V52EvidenceRegistry r = new V52EvidenceRegistry(address(0));
        assertFalse(r.issuers(issuer));
        assertFalse(r.issuers(address(0)));
    }

    function test_constructor_ownerIsNotAutomaticallyIssuer() public view {
        assertFalse(registry.issuers(owner));
    }

    // ─────────────────────────────────────────────────────────────────
    // setIssuer
    // ─────────────────────────────────────────────────────────────────

    function test_setIssuer_ownerCanAdd() public {
        vm.prank(owner);
        registry.setIssuer(otherIssuer, true);
        assertTrue(registry.issuers(otherIssuer));
    }

    function test_setIssuer_ownerCanRevoke() public {
        vm.prank(owner);
        registry.setIssuer(issuer, false);
        assertFalse(registry.issuers(issuer));
    }

    function test_setIssuer_emitsIssuerUpdated() public {
        vm.expectEmit(true, false, false, true);
        emit IssuerUpdated(otherIssuer, true);
        vm.prank(owner);
        registry.setIssuer(otherIssuer, true);
    }

    function test_setIssuer_revertsForNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(V52EvidenceRegistry.NotOwner.selector);
        registry.setIssuer(otherIssuer, true);
    }

    function test_setIssuer_revertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(V52EvidenceRegistry.ZeroAddress.selector);
        registry.setIssuer(address(0), true);
    }

    function test_setIssuer_revokedIssuerCannotAnchor() public {
        vm.prank(owner);
        registry.setIssuer(issuer, false);

        vm.prank(issuer);
        vm.expectRevert(V52EvidenceRegistry.NotIssuer.selector);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────
    // transferOwnership
    // ─────────────────────────────────────────────────────────────────

    function test_transferOwnership_updatesOwner() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);
        assertEq(registry.owner(), stranger);
    }

    function test_transferOwnership_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(owner, stranger);
        vm.prank(owner);
        registry.transferOwnership(stranger);
    }

    function test_transferOwnership_revertsForNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(V52EvidenceRegistry.NotOwner.selector);
        registry.transferOwnership(stranger);
    }

    function test_transferOwnership_revertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(V52EvidenceRegistry.ZeroAddress.selector);
        registry.transferOwnership(address(0));
    }

    function test_transferOwnership_oldOwnerLosesControl() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);

        vm.prank(owner);
        vm.expectRevert(V52EvidenceRegistry.NotOwner.selector);
        registry.setIssuer(otherIssuer, true);
    }

    function test_transferOwnership_newOwnerGainsControl() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);

        vm.prank(stranger);
        registry.setIssuer(otherIssuer, true);
        assertTrue(registry.issuers(otherIssuer));
    }

    // ─────────────────────────────────────────────────────────────────
    // anchorCase — happy path
    // ─────────────────────────────────────────────────────────────────

    function test_anchorCase_storesAnchor() public {
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));

        V52EvidenceRegistry.Anchor memory a = registry.getAnchor(ROOT_A);
        assertEq(a.manifestRoot, ROOT_A);
        assertEq(a.methodologyHash, METHOD_HASH);
        assertEq(a.schemaVersion, SCHEMA);
        assertEq(a.caseId, CASE_ID);
        assertEq(a.issuer, issuer);
        assertEq(a.blockNumber, uint64(block.number));
        assertEq(a.timestamp, uint64(block.timestamp));
        assertEq(a.supersedes, bytes32(0));
        assertTrue(a.exists);
    }

    function test_anchorCase_setsIsAnchoredTrue() public {
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        assertTrue(registry.isAnchored(ROOT_A));
    }

    function test_anchorCase_unseenRootIsNotAnchored() public view {
        assertFalse(registry.isAnchored(ROOT_A));
    }

    function test_anchorCase_updatesLatestManifestRootOf() public {
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        assertEq(registry.latestManifestRootOf(CASE_ID), ROOT_A);
        assertEq(registry.getLatestManifestRoot(CASE_ID), ROOT_A);
    }

    function test_anchorCase_incrementsAnchorCount() public {
        assertEq(registry.anchorCount(), 0);
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        assertEq(registry.anchorCount(), 1);
    }

    function test_anchorCase_emitsCaseAnchored() public {
        vm.expectEmit(true, true, false, true);
        emit CaseAnchored(
            ROOT_A,
            issuer,
            CASE_ID,
            SCHEMA,
            METHOD_HASH,
            bytes32(0),
            uint64(block.number),
            uint64(block.timestamp)
        );
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    function test_anchorCase_doesNotEmitSupersededWhenNotSuperseding() public {
        vm.recordLogs();
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 supersededTopic = keccak256("CaseSuperseded(bytes32,bytes32,string)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != supersededTopic);
        }
    }

    function test_anchorCase_allowsDifferentCasesWithDifferentRoots() public {
        vm.startPrank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        registry.anchorCase(ROOT_B, METHOD_HASH, SCHEMA, "case_1_other_000000_00000000", bytes32(0));
        vm.stopPrank();

        assertTrue(registry.isAnchored(ROOT_A));
        assertTrue(registry.isAnchored(ROOT_B));
        assertEq(registry.anchorCount(), 2);
    }

    function test_anchorCase_multipleIssuersCanAnchorDifferentRoots() public {
        vm.prank(owner);
        registry.setIssuer(otherIssuer, true);

        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));

        vm.prank(otherIssuer);
        registry.anchorCase(ROOT_B, METHOD_HASH, SCHEMA, "case_1_other_000000_00000000", bytes32(0));

        assertEq(registry.getAnchor(ROOT_A).issuer, issuer);
        assertEq(registry.getAnchor(ROOT_B).issuer, otherIssuer);
    }

    // ─────────────────────────────────────────────────────────────────
    // anchorCase — access control
    // ─────────────────────────────────────────────────────────────────

    function test_anchorCase_revertsForNonIssuer() public {
        vm.prank(stranger);
        vm.expectRevert(V52EvidenceRegistry.NotIssuer.selector);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    function test_anchorCase_revertsForOwnerWhoIsNotIssuer() public {
        vm.prank(owner);
        vm.expectRevert(V52EvidenceRegistry.NotIssuer.selector);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────
    // anchorCase — input validation
    // ─────────────────────────────────────────────────────────────────

    function test_anchorCase_revertsForZeroManifestRoot() public {
        vm.prank(issuer);
        vm.expectRevert(V52EvidenceRegistry.ZeroManifestRoot.selector);
        registry.anchorCase(bytes32(0), METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    function test_anchorCase_revertsForEmptyCaseId() public {
        vm.prank(issuer);
        vm.expectRevert(V52EvidenceRegistry.EmptyCaseId.selector);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, "", bytes32(0));
    }

    function test_anchorCase_revertsForDuplicateManifestRoot() public {
        vm.startPrank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(V52EvidenceRegistry.AlreadyAnchored.selector, ROOT_A)
        );
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        vm.stopPrank();
    }

    function test_anchorCase_duplicateAcrossDifferentIssuersStillReverts() public {
        vm.prank(owner);
        registry.setIssuer(otherIssuer, true);

        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));

        vm.prank(otherIssuer);
        vm.expectRevert(
            abi.encodeWithSelector(V52EvidenceRegistry.AlreadyAnchored.selector, ROOT_A)
        );
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    function test_anchorCase_revertsWhenSupersedesSelf() public {
        vm.prank(issuer);
        vm.expectRevert(V52EvidenceRegistry.SupersedesSelf.selector);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, ROOT_A);
    }

    function test_anchorCase_revertsWhenSupersedingUnknownRoot() public {
        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                V52EvidenceRegistry.UnknownSupersededManifestRoot.selector, ROOT_B
            )
        );
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, ROOT_B);
    }

    // ─────────────────────────────────────────────────────────────────
    // anchorCase — supersession flow
    // ─────────────────────────────────────────────────────────────────

    function test_anchorCase_supersession_updatesLatestPointer() public {
        vm.startPrank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        registry.anchorCase(ROOT_B, METHOD_HASH, SCHEMA, CASE_ID, ROOT_A);
        vm.stopPrank();

        assertEq(registry.latestManifestRootOf(CASE_ID), ROOT_B);
        assertEq(registry.getAnchor(ROOT_B).supersedes, ROOT_A);
    }

    function test_anchorCase_supersession_keepsOldAnchorReadable() public {
        vm.startPrank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        registry.anchorCase(ROOT_B, METHOD_HASH, SCHEMA, CASE_ID, ROOT_A);
        vm.stopPrank();

        assertTrue(registry.isAnchored(ROOT_A));
        assertEq(registry.getAnchor(ROOT_A).caseId, CASE_ID);
    }

    function test_anchorCase_supersession_emitsBothEvents() public {
        vm.prank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));

        vm.expectEmit(true, true, false, true);
        emit CaseSuperseded(ROOT_A, ROOT_B, CASE_ID);
        vm.prank(issuer);
        registry.anchorCase(ROOT_B, METHOD_HASH, SCHEMA, CASE_ID, ROOT_A);
    }

    function test_anchorCase_supersessionChain_threeVersions() public {
        bytes32 rootC = keccak256("manifest-c");
        vm.startPrank(issuer);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
        registry.anchorCase(ROOT_B, METHOD_HASH, SCHEMA, CASE_ID, ROOT_A);
        registry.anchorCase(rootC, METHOD_HASH, SCHEMA, CASE_ID, ROOT_B);
        vm.stopPrank();

        assertEq(registry.latestManifestRootOf(CASE_ID), rootC);
        assertEq(registry.getAnchor(rootC).supersedes, ROOT_B);
        assertEq(registry.getAnchor(ROOT_B).supersedes, ROOT_A);
        assertEq(registry.anchorCount(), 3);
    }

    // ─────────────────────────────────────────────────────────────────
    // View helpers on unknown data
    // ─────────────────────────────────────────────────────────────────

    function test_getAnchor_unknownRootReturnsEmptyStruct() public view {
        V52EvidenceRegistry.Anchor memory a = registry.getAnchor(ROOT_A);
        assertFalse(a.exists);
        assertEq(a.manifestRoot, bytes32(0));
        assertEq(a.issuer, address(0));
    }

    function test_getLatestManifestRoot_unknownCaseReturnsZero() public view {
        assertEq(registry.getLatestManifestRoot("does_not_exist"), bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────
    // Fuzzing
    // ─────────────────────────────────────────────────────────────────

    function testFuzz_anchorCase_arbitraryRootAndCaseId(bytes32 root, string calldata caseId)
        public
    {
        vm.assume(root != bytes32(0));
        vm.assume(bytes(caseId).length > 0);

        vm.prank(issuer);
        registry.anchorCase(root, METHOD_HASH, SCHEMA, caseId, bytes32(0));

        assertTrue(registry.isAnchored(root));
        assertEq(registry.latestManifestRootOf(caseId), root);
    }

    function testFuzz_anchorCase_revertsForNonIssuerCaller(address caller) public {
        vm.assume(caller != issuer);
        vm.prank(caller);
        vm.expectRevert(V52EvidenceRegistry.NotIssuer.selector);
        registry.anchorCase(ROOT_A, METHOD_HASH, SCHEMA, CASE_ID, bytes32(0));
    }

    function testFuzz_setIssuer_onlyOwnerControlsAllowlist(address candidate) public {
        vm.assume(candidate != address(0));
        vm.prank(owner);
        registry.setIssuer(candidate, true);
        assertTrue(registry.issuers(candidate));

        vm.prank(owner);
        registry.setIssuer(candidate, false);
        assertFalse(registry.issuers(candidate));
    }
}
