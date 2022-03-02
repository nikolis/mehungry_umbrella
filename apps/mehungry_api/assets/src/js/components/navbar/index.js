import React from 'react';
import {FaBars} from 'react-icons/fa'
import SideBar from '../sidebar';
import {
  Nav,
  NavLink,
  Bars,
  NavMenu,
  NavBtn,
  NavBtnLink,
  MobileIcon
} from './NavbarElements';

const Navbar = ({toggle}) => {
  return (
    <>
      <Nav>
        <NavLink to='/'>
          <h1>AFDDAF</h1>
        </NavLink>
        <SideBar />
        <MobileIcon onClick={toggle}>
            <FaBars/>
        </MobileIcon>
        <NavMenu>
          <NavLink to='/about' activeStyle={{ color:'red' }}>
            About
          </NavLink>
          
          <NavLink to='/create' activeStyle={{ color:'red' }}>
            Create
          </NavLink>
          <NavLink to='/contact-us' activeStyle={{ color:'red' }}>
            Contact Us
          </NavLink>
          <NavLink to='/sign-up' activeStyle={{ color:'red' }}>
            Sign Up
          </NavLink>
          {/* Second Nav */}
          {/* <NavBtnLink to='/sign-in'>Sign In</NavBtnLink> */}
        </NavMenu>
        <NavBtn>
          <NavBtnLink to='/signin'>Sign In</NavBtnLink>
        </NavBtn>
      </Nav>
    </>
  );
};

export default Navbar;