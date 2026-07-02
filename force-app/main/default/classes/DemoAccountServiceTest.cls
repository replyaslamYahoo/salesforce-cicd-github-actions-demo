@isTest
private class DemoAccountServiceTest {
    @isTest
    static void updateDescription_setsAccountDescription() {
        Account acc = new Account(Name = 'CI/CD Demo Account');
        insert acc;

        Test.startTest();
        DemoAccountService.updateDescription(acc.Id, 'Updated by pipeline');
        Test.stopTest();

        Account updated = [SELECT Description FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Updated by pipeline', updated.Description);
    }
}
