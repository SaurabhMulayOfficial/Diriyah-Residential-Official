@isTest
private class RES_ExpressionEvaluatorTest {

    // ─── convertToPostfix ────────────────────────────────────────────────────

    @isTest
    static void testConvertToPostfix_simpleOperand() {
        List<String> result = RES_ExpressionEvaluator.convertToPostfix(new List<String>{'1'});
        Assert.areEqual(new List<String>{'1'}, result, 'Single operand should pass through unchanged');
    }

    @isTest
    static void testConvertToPostfix_andExpression() {
        // "1 AND 2" → ["1", "2", "AND"]
        List<String> tokens = new List<String>{'1', 'AND', '2'};
        List<String> result = RES_ExpressionEvaluator.convertToPostfix(tokens);
        Assert.areEqual(new List<String>{'1', '2', 'AND'}, result);
    }

    @isTest
    static void testConvertToPostfix_orExpression() {
        // "1 OR 2" → ["1", "2", "OR"]
        List<String> tokens = new List<String>{'1', 'OR', '2'};
        List<String> result = RES_ExpressionEvaluator.convertToPostfix(tokens);
        Assert.areEqual(new List<String>{'1', '2', 'OR'}, result);
    }

    @isTest
    static void testConvertToPostfix_parenthesised() {
        // "( 1 AND 2 ) OR 3" → ["1", "2", "AND", "3", "OR"]
        List<String> tokens = new List<String>{'(', '1', 'AND', '2', ')', 'OR', '3'};
        List<String> result = RES_ExpressionEvaluator.convertToPostfix(tokens);
        Assert.areEqual(new List<String>{'1', '2', 'AND', '3', 'OR'}, result);
    }

    @isTest
    static void testConvertToPostfix_emptyInput() {
        List<String> result = RES_ExpressionEvaluator.convertToPostfix(new List<String>());
        Assert.areEqual(0, result.size(), 'Empty input should yield empty output');
    }

    @isTest
    static void testConvertToPostfix_unmatchedOpenParen_droppedFromResult() {
        // Unmatched "(" should not appear in output
        List<String> tokens = new List<String>{'(', '1', 'AND', '2'};
        List<String> result = RES_ExpressionEvaluator.convertToPostfix(tokens);
        Assert.isFalse(result.contains('('), 'Unmatched "(" should not appear in postfix output');
    }

    // ─── evaluatePostfix helpers ─────────────────────────────────────────────

    private static RES_Assignment_Config__c makeConfig(String condition) {
        RES_Assignment_Config__c cfg = new RES_Assignment_Config__c();
        cfg.RES_Condition__c    = condition;
        cfg.RES_Record_Types__c = 'RES_Individual';
        insert cfg;
        return cfg;
    }

    private static RES_Assignment_Condition__c makeCondition(
            Id configId, Decimal order, String field, String operator, String value) {
        RES_Assignment_Condition__c cond = new RES_Assignment_Condition__c();
        cond.RES_Assignment_Config__c = configId;
        cond.RES_Order__c             = order;
        cond.RES_Field_Api_Name__c    = field;
        cond.RES_Operator__c          = operator;
        cond.RES_Value__c             = value;
        insert cond;
        return cond;
    }

    private static Lead makeLead(String lastName, String company) {
        Lead l = new Lead(LastName = lastName, Company = company, MobilePhone = '+915021321000');
        insert l;
        return l;
    }

    // ─── evaluatePostfix — single condition, all operators ──────────────────

    @isTest
    static void testEvaluatePostfix_equalTo_match() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Company', 'Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result, 'Equal To should match');
    }

    @isTest
    static void testEvaluatePostfix_equalTo_noMatch() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Company', 'Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Other');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'Equal To mismatch should return null');
    }

    @isTest
    static void testEvaluatePostfix_notEqualTo_match() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Company', 'Not Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Other');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result);
    }

    @isTest
    static void testEvaluatePostfix_contains_match() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Company', 'Contains', 'Acm');
        Lead l = makeLead('Doe', 'Acme Corp');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result);
    }

    @isTest
    static void testEvaluatePostfix_contains_nullActual() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        // Website is typically null on a freshly created Lead
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Website', 'Contains', 'acme');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'Contains with null actual should not match');
    }

    @isTest
    static void testEvaluatePostfix_lessThan_match() {
        // Use Title (a text field) to hold a numeric string — NumberOfEmployees is Integer
        // and l.get() returns Integer which cannot be cast to String in the evaluator.
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Title', 'Less Than', '100');
        Lead l = makeLead('Doe', 'Acme');
        l.Title = '50';
        update l;

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result);
    }

    @isTest
    static void testEvaluatePostfix_greaterThan_match() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Title', 'Greater Than', '10');
        Lead l = makeLead('Doe', 'Acme');
        l.Title = '50';
        update l;

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result);
    }

    @isTest
    static void testEvaluatePostfix_lessThan_invalidNumericValue() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Company', 'Less Than', 'notANumber');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'Non-numeric Less Than should gracefully return null');
    }

    @isTest
    static void testEvaluatePostfix_greaterThan_invalidNumericValue() {
        RES_Assignment_Config__c cfg  = makeConfig('1');
        RES_Assignment_Condition__c c = makeCondition(cfg.Id, 1, 'Company', 'Greater Than', 'notANumber');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'Non-numeric Greater Than should gracefully return null');
    }

    // ─── evaluatePostfix — compound expressions ──────────────────────────────

    @isTest
    static void testEvaluatePostfix_andExpression_bothTrue() {
        RES_Assignment_Config__c cfg   = makeConfig('1 AND 2');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company',  'Equal To', 'Acme');
        RES_Assignment_Condition__c c2 = makeCondition(cfg.Id, 2, 'LastName', 'Equal To', 'Doe');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c1, c2}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result, 'AND: both true should match');
    }

    @isTest
    static void testEvaluatePostfix_andExpression_oneFalse() {
        RES_Assignment_Config__c cfg   = makeConfig('1 AND 2');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company',  'Equal To', 'Acme');
        RES_Assignment_Condition__c c2 = makeCondition(cfg.Id, 2, 'LastName', 'Equal To', 'Smith');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c1, c2}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'AND: one false should not match');
    }

    @isTest
    static void testEvaluatePostfix_orExpression_oneFalse() {
        RES_Assignment_Config__c cfg   = makeConfig('1 OR 2');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company',  'Equal To', 'Acme');
        RES_Assignment_Condition__c c2 = makeCondition(cfg.Id, 2, 'LastName', 'Equal To', 'Smith');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c1, c2}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result, 'OR: one true should match');
    }

    @isTest
    static void testEvaluatePostfix_orExpression_bothFalse() {
        RES_Assignment_Config__c cfg   = makeConfig('1 OR 2');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company',  'Equal To', 'Nope');
        RES_Assignment_Condition__c c2 = makeCondition(cfg.Id, 2, 'LastName', 'Equal To', 'Smith');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c1, c2}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'OR: both false should not match');
    }

    @isTest
    static void testEvaluatePostfix_parenthesisedExpression() {
        // "(1 AND 2) OR 3" — conditions 1 & 2 both fail, condition 3 passes
        RES_Assignment_Config__c cfg   = makeConfig('(1 AND 2) OR 3');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company',  'Equal To', 'Nope');
        RES_Assignment_Condition__c c2 = makeCondition(cfg.Id, 2, 'LastName', 'Equal To', 'Smith');
        RES_Assignment_Condition__c c3 = makeCondition(cfg.Id, 3, 'Company',  'Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{
                cfg.Id => new List<RES_Assignment_Condition__c>{c1, c2, c3}
            },
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.areEqual(cfg.Id, result, '(1 AND 2) OR 3 should match via condition 3');
    }

    // ─── evaluatePostfix — edge / guard cases ────────────────────────────────

    @isTest
    static void testEvaluatePostfix_configNotInAssignmentMap_skipped() {
        RES_Assignment_Config__c cfg   = makeConfig('1');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company', 'Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Acme');

        // Pass an empty assignmentConfig map — config should be skipped
        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c1}},
            new Map<Id, RES_Assignment_Config__c>()
        );
        Assert.isNull(result, 'Config missing from assignmentConfig map should be skipped');
    }

    @isTest
    static void testEvaluatePostfix_emptyConditionsList_skipped() {
        RES_Assignment_Config__c cfg = makeConfig('1');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>()},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'Empty conditions list should be skipped');
    }

    @isTest
    static void testEvaluatePostfix_unknownOrderInExpression_skipped() {
        // Condition expression references order "5" but no condition has that order
        RES_Assignment_Config__c cfg   = makeConfig('5');
        RES_Assignment_Condition__c c1 = makeCondition(cfg.Id, 1, 'Company', 'Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Acme');

        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>{cfg.Id => new List<RES_Assignment_Condition__c>{c1}},
            new Map<Id, RES_Assignment_Config__c>{cfg.Id => cfg}
        );
        Assert.isNull(result, 'Unknown condition order should cause the config to be skipped');
    }

    @isTest
    static void testEvaluatePostfix_multipleConfigs_secondMatches() {
        RES_Assignment_Config__c cfg1  = makeConfig('1');
        RES_Assignment_Condition__c c1 = makeCondition(cfg1.Id, 1, 'Company', 'Equal To', 'Nope');

        RES_Assignment_Config__c cfg2  = makeConfig('1');
        RES_Assignment_Condition__c c2 = makeCondition(cfg2.Id, 1, 'Company', 'Equal To', 'Acme');
        Lead l = makeLead('Doe', 'Acme');

        Map<Id, List<RES_Assignment_Condition__c>> condMap = new Map<Id, List<RES_Assignment_Condition__c>>{
            cfg1.Id => new List<RES_Assignment_Condition__c>{c1},
            cfg2.Id => new List<RES_Assignment_Condition__c>{c2}
        };
        Map<Id, RES_Assignment_Config__c> cfgMap = new Map<Id, RES_Assignment_Config__c>{
            cfg1.Id => cfg1,
            cfg2.Id => cfg2
        };

        Id result = RES_ExpressionEvaluator.evaluatePostfix(l, condMap, cfgMap);
        // One of the two configs must be the match (cfg2)
        Assert.areEqual(cfg2.Id, result, 'Second config should be returned when first does not match');
    }

    @isTest
    static void testEvaluatePostfix_noConfigs_returnsNull() {
        Lead l = makeLead('Doe', 'Acme');
        Id result = RES_ExpressionEvaluator.evaluatePostfix(
            l,
            new Map<Id, List<RES_Assignment_Condition__c>>(),
            new Map<Id, RES_Assignment_Config__c>()
        );
        Assert.isNull(result);
    }
}
