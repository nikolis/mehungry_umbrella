import { useState } from "react";
import IngredientSearchbox from "./IngredientSearchbox";
import styled from 'styled-components';
import { Button } from "@mui/material";
import {  useDispatch } from 'react-redux';
import {closeModal} from '../../actions'



function RecipeIngredientForm ( {onSearch, ingredients, addIngredientEntry }){
    const [unit, setUnit] = useState('')
    const [ingredient, setIngredient] = useState({})
    const [quantity, setQuantity] = useState('')
    const dispatch = useDispatch();

    const closeModalIng = () => {
        dispatch(closeModal())
      }
    
    const saveAndExist = () => {
        console.log(ingredient);
        addIngredientEntry({ id: ingredient[0].id, label: ingredient[0].label, measurement_unit: unit, quantity: quantity });
        closeModalIng();
    }
    
    return (
        <div className="flex">
      
                <IngredientSearchbox onSearch = {onSearch} ingredients = {ingredients} setIngredient={setIngredient}/>
                
                <input type="text" placeholder="Measurement Unit"
                value={unit}
                style={{width: "20%"}}
                onChange={(e) => setUnit(e.target.value)}
                />

                <input type="text" 
                style={{width: "20%"}}
                placeholder="quantity"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)} />
                <Button aria-label='Add' onClick={saveAndExist}/>
        </div>
    )

}

export default RecipeIngredientForm
