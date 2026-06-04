@IsTest
private class RES_MobileNumberServiceTest {

    @IsTest
    static void shouldPrefixDialCodeWhenMobileDoesNotStartWithPlus() {
        Lead oldLead = new Lead(
            Id = '00Q000000000001AAA',
            LastName = 'Old Lead',
            Company = 'Test Company',
            MobilePhone = '+966501234567',
            Country = 'Saudi Arabia'
        );

        Lead newLead = new Lead(
            Id = oldLead.Id,
            LastName = 'Old Lead',
            Company = 'Test Company',
            MobilePhone = '501234567',
            Country = 'Saudi Arabia'
        );

        Test.startTest();
        RES_MobileNumberService.normalizeLeadMobileNumbers(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead }
        );
        Test.stopTest();

        System.assertEquals(
            '+966501234567',
            newLead.MobilePhone,
            'Country dial code should be prefixed.'
        );
    }

    @IsTest
    static void shouldNotChangeMobileWhenAlreadyStartsWithPlus() {
        Lead oldLead = new Lead(
            Id = '00Q000000000002AAA',
            LastName = 'Old Lead',
            Company = 'Test Company',
            MobilePhone = '+966501234567',
            Country = 'Saudi Arabia'
        );

        Lead newLead = new Lead(
            Id = oldLead.Id,
            LastName = 'Old Lead',
            Company = 'Test Company',
            MobilePhone = '+966555555555',
            Country = 'Saudi Arabia'
        );

        Test.startTest();
        RES_MobileNumberService.normalizeLeadMobileNumbers(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead }
        );
        Test.stopTest();

        System.assertEquals(
            '+966555555555',
            newLead.MobilePhone,
            'Mobile number already in E.164 format should not be changed.'
        );
    }

    @IsTest
    static void shouldNotChangeMobileWhenCountryIsBlank() {
        Lead oldLead = new Lead(
            Id = '00Q000000000003AAA',
            LastName = 'Old Lead',
            Company = 'Test Company',
            MobilePhone = '+966501234567',
            Country = 'Saudi Arabia'
        );

        Lead newLead = new Lead(
            Id = oldLead.Id,
            LastName = 'Old Lead',
            Company = 'Test Company',
            MobilePhone = '501234567',
            Country = null
        );

        Test.startTest();
        RES_MobileNumberService.normalizeLeadMobileNumbers(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead }
        );
        Test.stopTest();

        System.assertEquals(
            '501234567',
            newLead.MobilePhone,
            'Mobile number should not change when Country is blank.'
        );
    }

    @IsTest
    static void shouldReturnSafelyForNullInputs() {
        Test.startTest();
        RES_MobileNumberService.normalizeLeadMobileNumbers(null, null);
        RES_MobileNumberService.normalizeLeadMobileNumbers(new List<Lead>(), new Map<Id, Lead>());
        RES_MobileNumberService.normalizeLeadMobileNumbers(new List<Lead>{ new Lead() }, null);
        Test.stopTest();

        System.assert(true, 'Method should safely return without exception.');
    }
}