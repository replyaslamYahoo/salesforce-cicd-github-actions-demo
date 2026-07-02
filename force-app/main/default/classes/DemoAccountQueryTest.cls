@isTest
private class DemoAccountQueryTest {
    @isTest
    static void getById_returnsAccount() {
        Account expected = new Account(Name = 'Demo Query Account', Description = 'initial');
        insert expected;

        Account actual = new DemoAccountQuery().getById(expected.Id);

        System.assertNotEquals(null, actual);
        System.assertEquals(expected.Id, actual.Id);
        System.assertEquals('Demo Query Account', actual.Name);
    }
}
