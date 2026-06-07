public with sharing class RES_ExpressionEvaluator {
    public RES_ExpressionEvaluator() {}

    public static List<String> convertToPostfix(List<String> expression){
        Stack stack = new Stack();
        List<String> result = new List<String>();

        for(String s: expression){
            if(s != 'AND' && s != 'OR' && s != '(' && s != ')'){
                result.add(s);
            }
            else if(s == ')'){
                while(!stack.isEmpty() && (String)stack.peek() != '('){
                    String res = (String) stack.pop();
                    result.add(res);
                }
                
                if(!stack.isEmpty() && (String)stack.peek() == '('){
                    stack.pop();
                }
            }
            else if(s == 'AND' || s == 'OR' || s == '('){
                stack.push(s);
            }
        }

        while(!stack.isEmpty()){
            String top = (String)stack.pop();
            if(top != '('){
                result.add(top);
            }
        }

        System.debug('Postfix Expression: ' + result);
        System.debug('Postfix Expression Size: ' + result.size());
        return result;
    }


    public static Id evaluatePostfix(Lead l, Map<Id, List<RES_Assignment_Condition__c>> configConditions, Map<Id, RES_Assignment_Config__c> assignmentConfig){

        for(Id configId: configConditions.keySet()){

            if(!assignmentConfig.containsKey(configId))continue;
            RES_Assignment_Config__c config = assignmentConfig.get(configId);
            String infixExpression = config.RES_Condition__c;
            infixExpression = infixExpression.replace('(', ' ( ');
            infixExpression = infixExpression.replace(')', ' ) ');
            List<String> tokens = new List<String>();

            for (String token : infixExpression.split('\\s+')) {
                if (!String.isBlank(token)) {
                    tokens.add(token);
                }
            }
            List<String> expression = convertToPostfix(tokens);

            System.debug('Tokens ' + tokens);

            Map<String, RES_Assignment_Condition__c> orderMapping = new Map<String, RES_Assignment_Condition__c>();
            List<RES_Assignment_Condition__c> conditions = configConditions.get(configId);
            if(conditions.isEmpty())continue;

            for(RES_Assignment_Condition__c condition: conditions){
                String order = String.valueOf(condition.RES_Order__c);
                orderMapping.put(order, condition);
            }

            Stack stack = new Stack();

            for(String s: expression){
                if(s != 'AND' && s != 'OR'){
                    System.debug('condition Order '+ s);
                    RES_Assignment_Condition__c c;

                    if(orderMapping.containsKey(s)){
                        c = orderMapping.get(s);
                    }else{
                        break;
                    }

                    String actualValue = (String) l.get(c.RES_Field_Api_Name__c);
                    String operator = (String) c.RES_Operator__c;
                    String expectedValue = (String) c.RES_Value__c;

                    Boolean result;

                    if(operator == 'Equal To'){
                        result = actualValue == expectedValue;
                    }else if(operator == 'Not Equal To'){
                        result = actualValue != expectedValue;
                    }else if(operator == 'Contains'){
                        result = actualValue != null && actualValue.contains(expectedValue);
                    }else if(operator == 'Less Than'){
                        try{
                            Decimal actual = Decimal.valueOf(actualValue);
                            Decimal expected = Decimal.valueOf(expectedValue);
                            result = actual < expected;
                        }catch(Exception e){
                            System.debug('Error in evaluating condition: ' + e.getMessage());
                            result = false;
                        }
                    }else if(operator == 'Greater Than'){
                        try{
                            Decimal actual = Decimal.valueOf(actualValue);
                            Decimal expected = Decimal.valueOf(expectedValue);
                            result = actual > expected;
                        }catch(Exception e){
                            System.debug('Error in evaluating condition: ' + e.getMessage());
                            result = false;
                        }
                    }

                    stack.push(result);    
                }
                else{
                    if(stack.size() < 2){
                        break;
                    }
                    
                    Boolean result_1 = (Boolean) stack.pop();
                    Boolean result_2 = (Boolean) stack.pop();
                    Boolean evaluatedResult;

                    if(s == 'AND'){
                        evaluatedResult = (result_1 && result_2);
                    }
                    else if(s == 'OR'){
                        evaluatedResult = (result_1 || result_2);
                    }

                    stack.push(evaluatedResult);
                }
            }

            if(stack.size() != 1){
                continue;
            }

            Boolean finalResult = (Boolean) stack.pop();

            if(finalResult == true){
                return configId;
            }
        }

        return null;
    }
}