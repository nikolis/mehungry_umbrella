import React from 'react'
import RecipeIngredientForm from './RecipeIngredientForm'
import styled from 'styled-components';
import {Modal} from '../Modal';
import { useState } from 'react';
import { NavLink as Link } from 'react-router-dom';
import {closeModal, showIngredientModal} from '../../actions'
import { useSelector, useDispatch } from 'react-redux';
import { Step } from '@mui/material';

const Button = styled.button`
  min-width: 100px;
  padding: 16px 32px;
  border-radius: 4px;
  border: none;
  background: #141414;
  color: #fff;
  font-size: 24px;
  cursor: pointer;
`;


const Container = styled.div`
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100vh;
`;


const RecipeForm = ({onSearch, ingredients}) => {
  const dispatch = useDispatch();
  const initialValue = [{ id: 0, label: "Some label", measurement_unit: 'some measurement unit', quantity: 23.4 }];
  const initialStep = [{text: "", index: 0}]
  const [ingredientEntries, setIngredientEntries] = useState(initialValue)
  const [steps, setSteps] = useState(initialStep)

  
  const listItems = ingredientEntries.map((number) =>
        <li>{number.label}/ {number.id}/{number.measurement_unit}/{number.quantity}</li>
  );
    
  const changeStep = (e) => {
    console.log("id")
    console.log(e.nativeEvent.srcElement.attributes.id.value);
    const step = steps.filter(st => String(st.index) === e.nativeEvent.srcElement.attributes.id.value)
    const steps_rest = steps.filter(st => String(st.index) !== e.nativeEvent.srcElement.attributes.id.value)
    step[0].text = e.target.value
    const new_ar  = [...step, ...steps_rest]
    setSteps(new_ar.sort(st => st.index))
  };
  
  const listSteps = steps.map((step) =>
    <input style={{
      "borderStyle": "solid"}, {"border-width": "5px"}} type="text" value={step.text} onChange={changeStep} id={step.index}/>
  );

  const openIngredientModal = () => {
    dispatch(showIngredientModal())
  }

  const addIngredientEntry = (item) => {
    const newList = ingredientEntries.concat(item);
    setIngredientEntries(newList);
  }
  const addStep = () => {
      const max_i = steps.sort( ste => ste.index)[0].index;  
      const new_steps  = [...steps, ...[{text: "", index: max_i+1}]]
      setSteps(new_steps.sort(step_t => step_t.index))
  }

  const closeModal = () => {
    dispatch(closeModal())
  }

  const modalOpen = () => {
    const modalVal =  useSelector(state => state.modalReducer);
    switch (modalVal) {
      case "INGREDIENT":
        return true;
      default: 
        return false;
    }
  }

  const showModal = modalOpen();

    return (
      <>
        {modalOpen() ? (<Modal showModal={showModal} onSearch = {onSearch} ingredients = {ingredients} addIngredientEntry = {addIngredientEntry} />) : null}
        {listItems}
        <Button onClick={openIngredientModal}>Add Ingredient</Button> 
        {listSteps}
        <Button onClick={addStep}>Add Step</Button> 

      </>
  )
}

export default RecipeForm