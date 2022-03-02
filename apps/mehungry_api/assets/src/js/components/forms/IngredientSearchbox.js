import * as React from 'react';
import TextField from '@mui/material/TextField';
import Autocomplete from '@mui/material/Autocomplete';
import { useState } from 'react';
import { FormControlUnstyledContext } from '@mui/core';


const IngredientSearchbox = ({onSearch, ingredients, setIngredient}) => {

  const [searchText, setSearchText] = useState("");

  const handleChange = (e) => {
    // console.log("change")
    // console.log(e)
    // console.log(e.target.value)
    // //console.log(e.value[0])
    // console.log(e.target.innerText)
    // console.log(ingredients)

    //names.filter(name => name.includes('J'))
    const ingr = ingredients.filter(ingre => ingre.label === e.target.innerText)
    setIngredient(ingr)
  } 

  const handleInput = (e) => {
    const text = e.target.value
    setSearchText(text);
    onSearch(searchText);
  }


  return (
    <Autocomplete
      style={{width: "40%"}}
      disablePortal
      id="combo-box-demo"
      options= {ingredients}
      onInputChange={handleInput}
      onChange = {handleChange}
      sx={{ width: 300 }}
      renderInput={(params) => <TextField {...params} label="Ingredient" />}
    />
  );
}

const movies = [
];

export default IngredientSearchbox