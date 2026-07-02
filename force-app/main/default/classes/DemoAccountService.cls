public without sharing class DemoAccountService {
    public static void updateDescription(Id accountId, String description) {
        update new Account(Id = accountId, Description = description);
    }
}
