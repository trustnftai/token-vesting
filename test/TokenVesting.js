const { expect } = require("chai");

/*
 * TEST SUMMARY
 * deploy vesting contract
 * send tokens to vesting contract (100 tokens)
 * create new vesting schedule (100 tokens)
 * check that vested amount is 0
 * set time to half the vesting period
 * check that vested amount is half the total amount to vest (50 tokens)
 * check that only beneficiary can try to release vested tokens
 * check that beneficiary cannot release more than the vested amount
 * release 10 tokens and check that a Transfer event is emitted with a value of 10
 * check that the released amount is 10
 * check that the vested amount is now 40
 * set current time after the end of the vesting period
 * check that the vested amount is 90 (100 - 10 released tokens)
 * release all vested tokens (90)
 * check that the number of released tokens is 100
 * check that the vested amount is 0
 */

describe("TokenVesting", function () {
  let Token;
  let testToken;
  let TokenVesting;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  before(async function () {
    Token = await ethers.getContractFactory("Token");
    TokenVesting = await ethers.getContractFactory("MockTokenVesting");
  });

  beforeEach(async function () {
    [owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();
    testToken = await Token.deploy("Test Token", "TT", 1000000);
    await testToken.deployed();
  });

  describe("Vesting", function () {
    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await testToken.balanceOf(owner.address);
      expect(await testToken.totalSupply()).to.equal(ownerBalance);
    });

    it("Should vest tokens after 9 months", async function () {
      // deploy vesting contract
      const tokenVesting = await TokenVesting.deploy(testToken.address);
      await tokenVesting.deployed();
      expect((await tokenVesting.getToken()).toString()).to.equal(
        testToken.address
      );

      const dayDuration = 86400; // in seconds
      const baseTime = 1638102492;
      const startTime = baseTime;
      const totalAmount = 1000;

      const schedules = [
        [addr1.address, baseTime, 100, false],
        [addr2.address, baseTime, 200, false],
        [addr3.address, baseTime + 86400 * 30, 300, false],
      ];

      // send tokens to vesting contract
      await expect(testToken.transfer(tokenVesting.address, totalAmount))
        .to.emit(testToken, "Transfer")
        .withArgs(owner.address, tokenVesting.address, totalAmount);
      const vestingContractBalance = await testToken.balanceOf(
        tokenVesting.address
      );
      expect(vestingContractBalance).to.equal(totalAmount);

      // create new vesting schedule
      await tokenVesting.createVestingSchedules(schedules.slice(0, 1));
      await tokenVesting.createVestingSchedules(schedules.slice(1, 3));

      // do not allow to create new schedule for already added address
      await expect(
        tokenVesting.createVestingSchedule(addr1.address, baseTime, 100)
      ).to.be.revertedWith(
        "TokenVesting: vesting schedule for address already initialized"
      );

      // make sure withdrawable amount and schedules count is correct
      const withdrawableAmount = await tokenVesting.getWithdrawableAmount();
      const schedulesCount = await tokenVesting.getVestingSchedulesCount();

      expect(withdrawableAmount).to.be.equal(400);
      expect(schedulesCount).to.be.equal(3);

      // check that only beneficiary can try to release vested tokens
      await expect(
        tokenVesting.connect(addr2).release(addr1.address)
      ).to.be.revertedWith(
        "TokenVesting: only beneficiary and owner can release vested tokens"
      );

      // check that beneficiary cannot release early for first schedule
      const beneficiary1 = addr1;
      await expect(
        tokenVesting.connect(beneficiary1).release(beneficiary1.address)
      ).to.be.revertedWith("TokenVesting: vesting date not yet reached");

      // try to release 1 day before vesting
      await tokenVesting.setCurrentTime(startTime + dayDuration * 269);
      await expect(
        tokenVesting.connect(beneficiary1).release(beneficiary1.address)
      ).to.be.revertedWith("TokenVesting: vesting date not yet reached");

      // try to release just when vesting finished
      await tokenVesting.setCurrentTime(startTime + dayDuration * 270);
      await expect(
        tokenVesting.connect(beneficiary1).release(beneficiary1.address)
      )
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary1.address, schedules[0][2]);

      // try to release again
      await expect(
        tokenVesting.connect(beneficiary1).release(beneficiary1.address)
      ).to.be.revertedWith(
        "TokenVesting: cannot release tokens, already vested"
      );

      // check that beneficiary cannot release early for second schedule
      const beneficiary2 = addr2;
      await expect(
        tokenVesting.connect(beneficiary2).release(beneficiary1.address)
      ).to.be.revertedWith(
        "TokenVesting: only beneficiary and owner can release vested tokens"
      );

      // try to release 1 day before vesting
      await tokenVesting.setCurrentTime(startTime + dayDuration * 269);
      await expect(
        tokenVesting.connect(beneficiary2).release(beneficiary2.address)
      ).to.be.revertedWith("TokenVesting: vesting date not yet reached");

      // try to release just when vesting finished
      await tokenVesting.setCurrentTime(startTime + dayDuration * 270);
      await expect(
        tokenVesting.connect(beneficiary2).release(beneficiary2.address)
      )
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary2.address, schedules[1][2]);
    });
  });
});
