// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title FundMultisig — K-of-N 多签执行
/// @notice 由初始 owners 集合 + threshold 设定。任一 owner 可 submit；K 名 owner 确认后任一 owner
///         可 execute。Owners 与 threshold 由多签自身（K-of-N）修改。
contract FundMultisig {
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint8 confirmations;
    }

    address[] private _owners;
    mapping(address => bool) public isOwner;
    uint8 public threshold;

    Transaction[] private _txs;
    mapping(uint256 => mapping(address => bool)) public confirmedBy;

    event OwnersSet(address[] owners, uint8 threshold);
    event Submitted(uint256 indexed txId, address indexed proposer, address target, uint256 value, bytes data);
    event Confirmed(uint256 indexed txId, address indexed owner, uint8 confirmations);
    event Revoked(uint256 indexed txId, address indexed owner, uint8 confirmations);
    event Executed(uint256 indexed txId, bool success);

    error NotOwner();
    error AlreadyConfirmed();
    error NotConfirmed();
    error AlreadyExecuted();
    error InsufficientConfirmations();
    error ExecutionFailed();
    error InvalidConfig();
    error OnlySelf();

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    constructor(address[] memory owners_, uint8 threshold_) {
        _setOwners(owners_, threshold_);
    }

    function _setOwners(address[] memory owners_, uint8 threshold_) internal {
        if (owners_.length == 0 || threshold_ == 0 || threshold_ > owners_.length) revert InvalidConfig();
        // clear previous
        for (uint256 i = 0; i < _owners.length; ++i) {
            isOwner[_owners[i]] = false;
        }
        delete _owners;
        for (uint256 i = 0; i < owners_.length; ++i) {
            address o = owners_[i];
            if (o == address(0) || isOwner[o]) revert InvalidConfig();
            isOwner[o] = true;
            _owners.push(o);
        }
        threshold = threshold_;
        emit OwnersSet(owners_, threshold_);
    }

    /// @notice 自调用：通过 K-of-N 修改 owners / threshold。
    function setOwners(address[] calldata owners_, uint8 threshold_) external onlySelf {
        _setOwners(owners_, threshold_);
    }

    function submit(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256 txId) {
        txId = _txs.length;
        _txs.push(Transaction({ to: to, value: value, data: data, executed: false, confirmations: 0 }));
        emit Submitted(txId, msg.sender, to, value, data);
        _confirm(txId);
    }

    function confirm(uint256 txId) external onlyOwner {
        _confirm(txId);
    }

    function _confirm(uint256 txId) internal {
        Transaction storage t = _txs[txId];
        if (t.executed) revert AlreadyExecuted();
        if (confirmedBy[txId][msg.sender]) revert AlreadyConfirmed();
        confirmedBy[txId][msg.sender] = true;
        unchecked {
            t.confirmations += 1;
        }
        emit Confirmed(txId, msg.sender, t.confirmations);
    }

    function revoke(uint256 txId) external onlyOwner {
        Transaction storage t = _txs[txId];
        if (t.executed) revert AlreadyExecuted();
        if (!confirmedBy[txId][msg.sender]) revert NotConfirmed();
        confirmedBy[txId][msg.sender] = false;
        unchecked {
            t.confirmations -= 1;
        }
        emit Revoked(txId, msg.sender, t.confirmations);
    }

    function execute(uint256 txId) external onlyOwner {
        Transaction storage t = _txs[txId];
        if (t.executed) revert AlreadyExecuted();
        if (t.confirmations < threshold) revert InsufficientConfirmations();
        t.executed = true;
        (bool ok,) = t.to.call{value: t.value}(t.data);
        if (!ok) revert ExecutionFailed();
        emit Executed(txId, ok);
    }

    function txCount() external view returns (uint256) {
        return _txs.length;
    }

    function getTx(uint256 txId) external view returns (Transaction memory) {
        return _txs[txId];
    }

    function owners() external view returns (address[] memory) {
        return _owners;
    }

    receive() external payable {}
}
