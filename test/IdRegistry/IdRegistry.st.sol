// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {IdRegistryHarness} from "../Utils.sol";

contract IdRegistrySymTest is SymTest, Test {
    IdRegistryHarness idRegistry;
    address trustedCaller;

    address x;
    address y;

    function setUp() public {
        // Setup IdRegistry
        idRegistry = new IdRegistryHarness(address(0));

        trustedCaller = address(0x1000);
        idRegistry.setTrustedCaller(trustedCaller);

        // Register fids
        vm.prank(trustedCaller);
        idRegistry.trustedRegister(address(0x1001), address(0x2001));
        vm.prank(trustedCaller);
        idRegistry.trustedRegister(address(0x1002), address(0x2002));

        assert(idRegistry.idOf(address(0x1001)) == 1);
        assert(idRegistry.idOf(address(0x1002)) == 2);

        assert(idRegistry.getRecoveryOf(1) == address(0x2001));
        assert(idRegistry.getRecoveryOf(2) == address(0x2002));

        // Create symbolic addresses
        x = svm.createAddress("x");
        y = svm.createAddress("y");
    }

    // Additional setup to cover various input states
    function init() public {
        if (svm.createBool("disableTrustedOnly?")) {
            idRegistry.disableTrustedOnly();
        }
        if (svm.createBool("pauseRegistration?")) {
            idRegistry.pauseRegistration();
        }
    }

    // Verify the IdRegistry invariants
    function check_invariant(bytes4 selector, address caller) public {
        init();

        // Consider two distinct addresses
        vm.assume(x != y);

        // Record pre-state
        uint256 oldIdX = idRegistry.idOf(x);
        uint256 oldIdY = idRegistry.idOf(y);

        uint256 oldIdCounter = idRegistry.getIdCounter();

        bool oldPaused = idRegistry.paused();

        // Execute an arbitrary tx to IdRegistry
        vm.prank(caller);
        (bool success,) = address(idRegistry).call(mk_calldata(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        uint256 newIdX = idRegistry.idOf(x);
        uint256 newIdY = idRegistry.idOf(y);

        uint256 newIdCounter = idRegistry.getIdCounter();

        // Verify invariant properties

        // Ensure that there is no recovery address associated with fid 0.
        assert(idRegistry.getRecoveryOf(0) == address(0));

        // Ensure that idCounter never decreases.
        assert(newIdCounter >= oldIdCounter);

        // If a new fid is registered, ensure that:
        // - IdRegistry must not be paused.
        // - idCounter must increase by 1.
        // - The new fid must not be registered for an existing fid owner.
        // - The existing fids must be preserved.
        if (newIdCounter > oldIdCounter) {
            assert(oldPaused == false);
            assert(newIdCounter - oldIdCounter == 1);
            assert(newIdX == oldIdX || oldIdX == 0);
            assert(newIdX == oldIdX || newIdY == oldIdY);
        }
    }

    function mk_calldata(bytes4 selector) internal returns (bytes memory) {
        // Generate calldata based on the function selector
        bytes memory args;
        if (selector == idRegistry.registerFor.selector) {
            args = abi.encode(
                svm.createAddress("to"),
                svm.createAddress("recovery"),
                svm.createUint256("deadline"),
                svm.createBytes(65, "sig")
            );
        } else if (selector == idRegistry.transfer.selector) {
            args = abi.encode(svm.createAddress("to"), svm.createUint256("deadline"), svm.createBytes(65, "sig"));
        } else if (selector == idRegistry.recover.selector) {
            args = abi.encode(
                svm.createAddress("from"),
                svm.createAddress("to"),
                svm.createUint256("deadline"),
                svm.createBytes(65, "sig")
            );
        } else {
            args = svm.createBytes(1024, "data");
        }
        return abi.encodePacked(selector, args);
    }

    function check_transfer(address caller, address to, address other) public {
        init();

        // Consider another address that is not involved
        vm.assume(other != caller && other != to);

        // Record pre-state
        uint256 oldIdCaller = idRegistry.idOf(caller);
        uint256 oldIdTo = idRegistry.idOf(to);
        uint256 oldIdOther = idRegistry.idOf(other);

        // Execute transfer with symbolic arguments
        vm.prank(caller);
        idRegistry.transfer(to, svm.createUint256("deadline"), svm.createBytes(65, "sig"));

        // Record post-state
        uint256 newIdCaller = idRegistry.idOf(caller);
        uint256 newIdTo = idRegistry.idOf(to);
        uint256 newIdOther = idRegistry.idOf(other);

        // Verify correctness properties

        // Ensure that the fid has been transferred from the `caller` to the `to`.
        assert(newIdTo == oldIdCaller);
        if (caller != to) {
            assert(oldIdCaller != 0 && newIdCaller == 0);
            assert(oldIdTo == 0 && newIdTo != 0);
        }

        // Ensure that the other fids are not affected.
        assert(newIdOther == oldIdOther);
    }

    function check_recover(address caller, address from, address to, address other) public {
        init();

        // Consider other address that is not involved
        vm.assume(other != from && other != to);

        // Record pre-state
        uint256 oldIdFrom = idRegistry.idOf(from);
        uint256 oldIdTo = idRegistry.idOf(to);
        uint256 oldIdOther = idRegistry.idOf(other);

        address oldRecoveryFrom = idRegistry.getRecoveryOf(oldIdFrom);

        // Execute recover with symbolic arguments
        vm.prank(caller);
        idRegistry.recover(from, to, svm.createUint256("deadline"), svm.createBytes(65, "sig"));

        // Record post-state
        uint256 newIdFrom = idRegistry.idOf(from);
        uint256 newIdTo = idRegistry.idOf(to);
        uint256 newIdOther = idRegistry.idOf(other);

        // Verify correctness properties

        // Ensure that the caller is the recovery address
        assert(caller == oldRecoveryFrom);

        // Ensure that the fid has been transferred from the `from` to the `to`.
        assert(newIdTo == oldIdFrom);
        if (from != to) {
            assert(oldIdFrom != 0 && newIdFrom == 0);
            assert(oldIdTo == 0 && newIdTo != 0);
        }

        // Ensure that the other fids are not affected.
        assert(newIdOther == oldIdOther);
    }
}