// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title TokenVesting
 */
contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct VestingSchedule {
        // beneficiary of tokens after they are released
        address beneficiary;
        // start time of the vesting period
        uint256 start;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // are tokens released for beneficiary
        bool released;
    }

    // address of the ERC20 token
    IERC20 private immutable _token;

    address[] private vestingSchedulesAddresses;
    mapping(address => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;
    uint256 private vestingDuration = 270 days;

    event Released(uint256 amount);
    event Revoked();

    /**
     * @dev Creates a vesting contract.
     * @param token_ address of the ERC20 token contract
     */
    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @notice Returns the total amount of vesting schedules.
     * @return the total amount of vesting schedules
     */
    function getVestingSchedulesTotalAmount() external view returns (uint256) {
        return vestingSchedulesTotalAmount;
    }

    /**
     * @dev Returns the address of the ERC20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }

    /**
     * @notice Creates new vesting schedules.
     * @param _vestingSchedules array of vesting schedules to create.
     */
    function createVestingSchedules(VestingSchedule[] memory _vestingSchedules)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < _vestingSchedules.length; i++) {
            createVestingSchedule(
                _vestingSchedules[i].beneficiary,
                _vestingSchedules[i].start,
                _vestingSchedules[i].amountTotal
            );
        }
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _amount
    ) public onlyOwner {
        require(
            this.getWithdrawableAmount() >= _amount,
            "TokenVesting: cannot create vesting schedule because not sufficient tokens"
        );
        require(_amount > 0, "TokenVesting: amount must be > 0");
        require(
            vestingSchedules[_beneficiary].beneficiary == address(0),
            "TokenVesting: vesting schedule for address already initialized"
        );

        vestingSchedules[_beneficiary] = VestingSchedule(
            _beneficiary,
            _start,
            _amount,
            false
        );

        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        vestingSchedulesAddresses.push(_beneficiary);
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant onlyOwner {
        require(
            this.getWithdrawableAmount() >= amount,
            "TokenVesting: not enough withdrawable funds"
        );
        _token.safeTransfer(owner(), amount);
    }

    /**
     * @notice Release vested tokens.
     * @param addr the vesting schedule beneficiary
     */
    function release(address addr) public nonReentrant {
        VestingSchedule storage vestingSchedule = vestingSchedules[addr];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(
            isBeneficiary || isOwner,
            "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        require(
            vestingSchedule.released == false,
            "TokenVesting: cannot release tokens, already vested"
        );

        uint256 currentTime = getCurrentTime();
        require(
            currentTime >= vestingSchedule.start + vestingDuration,
            "TokenVesting: vesting date not yet reached"
        );

        vestingSchedule.released = true;
        address payable beneficiaryPayable = payable(
            vestingSchedule.beneficiary
        );
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(
            vestingSchedule.amountTotal
        );
        _token.safeTransfer(beneficiaryPayable, vestingSchedule.amountTotal);
    }

    /**
     * @dev Returns the number of vesting schedules managed by this contract.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCount() public view returns (uint256) {
        return vestingSchedulesAddresses.length;
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(address addr)
        public
        view
        returns (VestingSchedule memory)
    {
        return vestingSchedules[addr];
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return _token.balanceOf(address(this)).sub(vestingSchedulesTotalAmount);
    }

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
