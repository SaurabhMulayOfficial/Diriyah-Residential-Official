/**
 * Class Name: RES_MobileNumberService
 * Description: Service class used to normalize Lead mobile numbers into E.164 format
 *              by prefixing the correct country dial code when the number does not
 *              already start with plus sign.
 */
public with sharing class RES_MobileNumberService {
    private static final String COUNTRY_NAME = 'name';
    private static final String COUNTRY_CODE = 'code';
    private static final String DIAL_CODE = 'dial_code';

    /**
     * Normalizes mobile numbers for updated Lead records when mobile,
     * country, or country code changes.
     *
     * @param newLeads updated Lead records.
     * @param oldLeadMap old Lead values by Id.
     */
    public static void normalizeLeadMobileNumbers(
        List<Lead> newLeads,
        Map<Id, Lead> oldLeadMap
    ) {
        if (newLeads == null || newLeads.isEmpty() || oldLeadMap == null) {
            return;
        }

        Map<String, String> countryToDialCode = getCountryDialCodeMap();

        for (Lead leadRecord : newLeads) {
            Lead oldLead = oldLeadMap.get(leadRecord.Id);

            if (oldLead == null || isMobileAndCountryUnchanged(leadRecord, oldLead)) {
                continue;
            }

            normalizeLeadMobile(leadRecord, countryToDialCode);
        }
    }

    private static Boolean isMobileAndCountryUnchanged(Lead newLead, Lead oldLead) {
        return normalizeText(newLead.MobilePhone) == normalizeText(oldLead.MobilePhone)
            && normalizeText(newLead.Country) == normalizeText(oldLead.Country)
            && normalizeText(newLead.CountryCode) == normalizeText(oldLead.CountryCode);
    }

    private static void normalizeLeadMobile(
        Lead leadRecord,
        Map<String, String> countryToDialCode
    ) {
        if (
            String.isBlank(leadRecord.MobilePhone) ||
            leadRecord.MobilePhone.trim().startsWith('+')
        ) {
            return;
        }

        String countryValue = getLeadCountryValue(leadRecord);

        if (String.isBlank(countryValue)) {
            return;
        }

        String mobile = leadRecord.MobilePhone.trim().replaceAll('[^0-9]', '');
        String countryKey = countryValue.trim().toLowerCase();
        String dialCode = countryToDialCode.get(countryKey);

        if (String.isBlank(mobile) || String.isBlank(dialCode)) {
            return;
        }

        leadRecord.MobilePhone = dialCode + mobile;
    }

    private static String getLeadCountryValue(Lead leadRecord) {
        if (String.isNotBlank(leadRecord.CountryCode)) {
            return leadRecord.CountryCode;
        }

        return leadRecord.Country;
    }

    private static Map<String, String> getCountryDialCodeMap() {
        Map<String, String> countryToDialCode = new Map<String, String>();
        RES_CountryDialCodeDAOLayer dao = new RES_CountryDialCodeDAOLayer();
        StaticResource resource = dao.getCountryDialCodeResource();

        if (resource == null || resource.Body == null) {
            return countryToDialCode;
        }

        List<Object> countries =
            (List<Object>) JSON.deserializeUntyped(resource.Body.toString());

        for (Object countryObj : countries) {
            Map<String, Object> countryMap = (Map<String, Object>) countryObj;

            String countryName = (String) countryMap.get(COUNTRY_NAME);
            String countryCode = (String) countryMap.get(COUNTRY_CODE);
            String dialCode = (String) countryMap.get(DIAL_CODE);

            addCountryKey(countryToDialCode, countryName, dialCode);
            addCountryKey(countryToDialCode, countryCode, dialCode);
        }

        return countryToDialCode;
    }

    private static void addCountryKey(
        Map<String, String> countryToDialCode,
        String countryValue,
        String dialCode
    ) {
        if (String.isBlank(countryValue) || String.isBlank(dialCode)) {
            return;
        }

        countryToDialCode.put(
            countryValue.trim().toLowerCase(),
            dialCode.trim()
        );
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }
}