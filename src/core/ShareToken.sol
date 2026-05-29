// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {IKYCRegistry} from "../interfaces/IKYCRegistry.sol";

/// @title ShareToken — 基金份额代币
/// @notice ERC-20 + ERC-2612 Permit；mint/burn 仅授权地址可调；持有人之间转账要求双方 KYC 通过。
contract ShareToken is IShareToken, ERC20, ERC20Permit, Ownable {
    IKYCRegistry public immutable kyc;
    mapping(address => bool) public _minters;
    mapping(address => bool) public _burners;
    uint8 private immutable _decimals;

    error NotMinter();
    error NotBurner();
    error TransferRequiresKYC(address party);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address owner_, address kyc_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        Ownable(owner_)
    {
        require(kyc_ != address(0), "ST: kyc zero");
        kyc = IKYCRegistry(kyc_);
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setMinter(address account, bool authorized) external onlyOwner {
        _minters[account] = authorized;
        emit MinterSet(account, authorized);
    }

    function setBurner(address account, bool authorized) external onlyOwner {
        _burners[account] = authorized;
        emit BurnerSet(account, authorized);
    }

    function mint(address to, uint256 amount) external {
        if (!_minters[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (!_burners[msg.sender]) revert NotBurner();
        _burn(from, amount);
    }

    function isMinter(address account) external view returns (bool) {
        return _minters[account];
    }

    function isBurner(address account) external view returns (bool) {
        return _burners[account];
    }

    /// @dev OZ v5 transfer hook. Mint (from=0) 与 Burn (to=0) 不强制 KYC；
    ///      用户间转账（from!=0 && to!=0）要求双方均 KYC 通过。
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            if (!kyc.isApproved(from)) revert TransferRequiresKYC(from);
            if (!kyc.isApproved(to)) revert TransferRequiresKYC(to);
        }
        super._update(from, to, value);
    }
}
