// import CardList from '../CardList';
// import SearchBar from '../SearchBar'
import { useState } from 'react';
import IngredientSource from '../../api/IngredientSource'
import IngredientSearchbox from '../forms/IngredientSearchbox';
import RecipeForm from '../forms/RecipeForm';

const Create = () => {
    const  [state, setState] = useState(
        []
    )

    const onSearch = async (text) => {
        const results = await IngredientSource.get("/api/v1/ingredient/search", {
            params: {language: 1, name: text}
        })
        
        setState(prevState =>{
            
            let data =  results.data.data
            console.log(data);
            let data_proc = data.map((item) =>  ({label: item.name, id: item.id}) );
            console.log(data_proc);
            return data_proc
        })
    }

    return (
        <div className="container searchApp">
          
           <RecipeForm onSearch = {onSearch} ingredients = {state} />
           {/* <IngredientSearchbox onSearch = {onSearch} ingredients = {state}/> */}
        </div>
    )
}

export default Create
