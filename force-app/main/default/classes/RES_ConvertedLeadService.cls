/**
 * Class Name:  RES_ConvertedLeadService
 * Description: Service Class used to show the tab view of Converted Leads based on
 *              profiles and roles.
 */
public without sharing class RES_ConvertedLeadService {

    public class ConvertedLeadResponse {
        @AuraEnabled public String heading;
        @AuraEnabled public List<ConvertedLeadRow> leads;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer totalPages;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
    }

    public class ConvertedLeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String company;
        @AuraEnabled public String email;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String leadSourceLabel;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime convertedDate;
    }

    private class UserContext {
        Id userId;
        Id userRoleId;
        Id profileId;
    }

    @TestVisible private static List<Lead> testConvertedLeads;
    @TestVisible private static Id testAdminProfileId;
    @TestVisible private static Set<Id> testMyConvertedRoleIds;
    @TestVisible private static Set<Id> testMyTeamConvertedRoleIds;

    public static ConvertedLeadResponse getConvertedLeads(
        Integer pageNumber,
        Integer pageSize,
        String searchKey
    ) {
        UserContext currentUserContext = getCurrentUserContext();

        List<Lead> allLeads = filterConvertedLeads(
            getConvertedLeadSourceRecords(),
            currentUserContext
        );

        if (String.isNotBlank(searchKey)) {
            allLeads = filterBySearchKey(allLeads, searchKey.toLowerCase());
        }

        Integer total = allLeads.size();
        Integer safeSize = (pageSize != null && pageSize > 0) ? pageSize : 20;
        Integer totalPages = total == 0 ? 1 : (Integer) Math.ceil((Double) total / safeSize);
        Integer safePage = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
        if (safePage > totalPages) {
            safePage = totalPages;
        }

        Integer startIdx = (safePage - 1) * safeSize;
        Integer endIdx = Math.min(startIdx + safeSize, total);

        List<Lead> pageLeads = new List<Lead>();
        for (Integer i = startIdx; i < endIdx; i++) {
            pageLeads.add(allLeads[i]);
        }

        ConvertedLeadResponse response = new ConvertedLeadResponse();
        response.heading = getHeading(currentUserContext);
        response.leads = buildConvertedLeadRows(pageLeads);
        response.totalCount = total;
        response.totalPages = totalPages;
        response.pageNumber = safePage;
        response.pageSize = safeSize;

        return response;
    }

    private static List<Lead> getConvertedLeadSourceRecords() {
        if (
            Test.isRunningTest() &&
            testConvertedLeads != null
        ) {
            return testConvertedLeads;
        }

        return new RES_LeadDAOLayer().getConvertedLeads();
    }

    private static List<Lead> filterConvertedLeads(
        List<Lead> leads,
        UserContext currentUserContext
    ) {
        if (leads == null || leads.isEmpty()) {
            return new List<Lead>();
        }

        if (isAdminProfile(currentUserContext.profileId)) {
            return leads;
        }

        if (isMyConvertedRole(currentUserContext.userRoleId)) {
            return getMyConvertedLeads(
                leads,
                currentUserContext.userId
            );
        }

        if (isMyTeamConvertedRole(currentUserContext.userRoleId)) {
            return getMyTeamConvertedLeads(
                leads,
                currentUserContext
            );
        }

        return new List<Lead>();
    }

    private static List<Lead> getMyConvertedLeads(
        List<Lead> leads,
        Id currentUserId
    ) {
        List<Lead> filteredLeads = new List<Lead>();

        if (leads == null || leads.isEmpty() || currentUserId == null) {
            return filteredLeads;
        }

        for (Lead ld : leads) {
            if (ld.OwnerId == currentUserId) {
                filteredLeads.add(ld);
            }
        }

        return filteredLeads;
    }

    private static List<Lead> getMyTeamConvertedLeads(
        List<Lead> leads,
        UserContext currentUserContext
    ) {
        Set<Id> allowedOwnerIds = getSubordinateUserIdsByManager(
            currentUserContext.userId
        );

        allowedOwnerIds.add(currentUserContext.userId);

        List<Lead> filteredLeads = new List<Lead>();

        for (Lead ld : leads) {
            if (allowedOwnerIds.contains(ld.OwnerId)) {
                filteredLeads.add(ld);
            }
        }

        return filteredLeads;
    }

    private static Set<Id> getSubordinateUserIdsByManager(Id managerUserId) {
        Set<Id> allUserIds = new Set<Id>();

        if (managerUserId == null) {
            return allUserIds;
        }

        Set<Id> managerIds = new Set<Id>{ managerUserId };

        while (!managerIds.isEmpty()) {
            Set<Id> childUserIds = new Set<Id>();

            for (User usr : [
                SELECT Id
                FROM User
                WHERE IsActive = true
                AND ManagerId IN :managerIds
            ]) {
                childUserIds.add(usr.Id);
            }

            childUserIds.removeAll(allUserIds);

            if (childUserIds.isEmpty()) {
                break;
            }

            allUserIds.addAll(childUserIds);
            managerIds = childUserIds;
        }

        return allUserIds;
    }

    private static List<Lead> filterBySearchKey(
        List<Lead> leads,
        String lowerKey
    ) {
        List<Lead> filtered = new List<Lead>();
        for (Lead ld : leads) {
            String combined = (
                (ld.Name != null ? ld.Name : '') + ' ' +
                (ld.Owner != null && ld.Owner.Name != null ? ld.Owner.Name : '') + ' ' +
                (ld.Company != null ? ld.Company : '') + ' ' +
                (ld.Email != null ? ld.Email : '') + ' ' +
                (ld.MobilePhone != null ? ld.MobilePhone : '') + ' ' +
                (ld.Status != null ? ld.Status : '') + ' ' +
                (ld.LeadSource != null ? ld.LeadSource : '')
            ).toLowerCase();
            if (combined.contains(lowerKey)) {
                filtered.add(ld);
            }
        }
        return filtered;
    }

    private static List<ConvertedLeadRow> buildConvertedLeadRows(
        List<Lead> leads
    ) {
        Map<String, String> statusLabelMap = getPicklistValueLabelMap(
            Lead.Status
        );

        Map<String, String> leadSourceLabelMap = getPicklistValueLabelMap(
            Lead.LeadSource
        );

        List<ConvertedLeadRow> rows = new List<ConvertedLeadRow>();

        if (leads == null || leads.isEmpty()) {
            return rows;
        }

        for (Lead ld : leads) {
            ConvertedLeadRow row = new ConvertedLeadRow();
            row.id = ld.Id;
            row.name = ld.Name;
            row.ownerName = ld.Owner != null ? ld.Owner.Name : '';

            row.statusLabel = statusLabelMap.containsKey(ld.Status)
                ? statusLabelMap.get(ld.Status)
                : ld.Status;

            row.company = ld.Company;
            row.email = ld.Email;
            row.mobilePhone = ld.MobilePhone;

            row.leadSourceLabel = leadSourceLabelMap.containsKey(ld.LeadSource)
                ? leadSourceLabelMap.get(ld.LeadSource)
                : ld.LeadSource;

            row.createdDate = ld.CreatedDate;
            row.convertedDate = ld.ConvertedDate;

            rows.add(row);
        }

        return rows;
    }

    private static Map<String, String> getPicklistValueLabelMap(
        Schema.SObjectField fieldToken
    ) {
        Map<String, String> valueLabelMap = new Map<String, String>();

        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            valueLabelMap.put(entry.getValue(), entry.getLabel());
        }

        return valueLabelMap;
    }

    private static UserContext getCurrentUserContext() {
        UserContext context = new UserContext();
        context.userId = UserInfo.getUserId();
        context.userRoleId = UserInfo.getUserRoleId();
        context.profileId = UserInfo.getProfileId();

        return context;
    }

    private static String getHeading(UserContext currentUserContext) {
        if (isAdminProfile(currentUserContext.profileId)) {
            return 'All Converted Leads';
        }

        if (isMyTeamConvertedRole(currentUserContext.userRoleId)) {
            return 'My Team Converted Leads';
        }

        if (isMyConvertedRole(currentUserContext.userRoleId)) {
            return 'My Converted Leads';
        }

        return 'Converted Leads';
    }

    private static Boolean isAdminProfile(Id profileId) {
        if (
            Test.isRunningTest() &&
            testAdminProfileId != null
        ) {
            return profileId == testAdminProfileId;
        }

        if (
            profileId == null ||
            String.isBlank(System.Label.RES_Admin_All_Converted_Leads)
        ) {
            return false;
        }

        try {
            Id adminProfileId = Id.valueOf(
                System.Label.RES_Admin_All_Converted_Leads.trim()
            );

            return profileId == adminProfileId;
        } catch (Exception ex) {
            return false;
        }
    }

    private static Boolean isMyConvertedRole(Id roleId) {
        if (
            Test.isRunningTest() &&
            testMyConvertedRoleIds != null &&
            testMyConvertedRoleIds.contains(roleId)
        ) {
            return true;
        }

        return containsRoleId(
            roleId,
            System.Label.RES_My_Converted_Lead_Roles
        );
    }

    private static Boolean isMyTeamConvertedRole(Id roleId) {
        if (
            Test.isRunningTest() &&
            testMyTeamConvertedRoleIds != null &&
            testMyTeamConvertedRoleIds.contains(roleId)
        ) {
            return true;
        }

        return containsRoleId(
            roleId,
            System.Label.RES_My_Team_Converted_Lead_Roles
        );
    }

    private static Boolean containsRoleId(
        Id roleId,
        String labelValue
    ) {
        if (
            roleId == null ||
            String.isBlank(labelValue)
        ) {
            return false;
        }

        for (String labelRoleId : labelValue.split(';')) {
            try {
                Id configuredRoleId = Id.valueOf(labelRoleId.trim());

                if (roleId == configuredRoleId) {
                    return true;
                }
            } catch (Exception ex) {
                // Ignore invalid role id values in custom label.
            }
        }

        return false;
    }
}