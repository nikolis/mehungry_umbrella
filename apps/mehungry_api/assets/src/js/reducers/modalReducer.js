const modalReducer = (state = "", action) => {
    switch(action.type){
       case "INGREDIENT":
           return "INGREDIENT";
        default :
            return "";
    }
}


export default modalReducer;