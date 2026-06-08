public class Stack{
    public Stack() {}
    
    private List<Object> items = new List<Object>();

    public void push(Object item){
        items.add(item);
    }

    public Object pop(){
        if(items.isEmpty()){
            throw new IllegalArgumentException('Stack is empty');
        }
        return items.remove(items.size() - 1);
    }

    public Object peek() {
        if(items.isEmpty()){
            throw new IllegalArgumentException('Stack is empty');
        }
        return items[items.size() - 1];
    }

    public Boolean isEmpty(){
        return items.isEmpty();
    }

    public Integer size(){
        return items.size();
    }
}