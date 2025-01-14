// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {RecoveryProxyTestSuite} from "./RecoveryProxyTestSuite.sol";

/* solhint-disable state-visibility */

contract RecoveryProxyTest is RecoveryProxyTestSuite {
    function testIdRegistry() public {
        assertEq(address(recoveryProxy.idRegistry()), address(idRegistry));
    }

    function testInitialOwner() public {
        assertEq(recoveryProxy.owner(), owner);
    }

    function testFuzzRecoveryByProxy(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, address(recoveryProxy));
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));

        vm.prank(owner);
        recoveryProxy.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));
    }

    function testFuzzRecoveryByProxyRevertsUnauthorized(
        address from,
        uint256 toPk,
        uint40 _deadline,
        address caller
    ) public {
        vm.assume(caller != owner);
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, address(recoveryProxy));
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        recoveryProxy.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));
    }

    function testFuzzChangeOwner(address from, uint256 toPk, uint40 _deadline, address newOwner) public {
        vm.assume(newOwner != owner);
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, address(recoveryProxy));
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));

        vm.prank(owner);
        recoveryProxy.transferOwnership(newOwner);

        vm.prank(newOwner);
        recoveryProxy.acceptOwnership();

        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        recoveryProxy.recover(from, to, deadline, sig);

        vm.prank(newOwner);
        recoveryProxy.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.recoveryOf(1), address(recoveryProxy));
    }
}
