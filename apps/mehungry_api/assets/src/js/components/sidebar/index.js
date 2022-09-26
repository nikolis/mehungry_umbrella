import React from 'react'
import { SideBarContainer, Icon, ClosedIcon, 
    SidebarWrapper, SidebarMenu, 
    SidebarLink, SideBtnWrap, SidebarRoute, SidebarContainer } from './SidebarElements'

const SideBar = ({ isOpen, toggle }) => {
    return (
        <SidebarContainer isOpen={isOpen} onClick={toggle}>
            <Icon onClick={toggle}>
                <ClosedIcon />
            </Icon>
            <SidebarWrapper>
                <SidebarMenu>
                    <SidebarLink to="about">About </SidebarLink>
                    <SidebarLink to="create">Create</SidebarLink>
                    <SidebarLink to="contact-us">Contact Us</SidebarLink>
                </SidebarMenu>
                <SideBtnWrap>
                    <SidebarRoute to="/signin">Sign In</SidebarRoute>
                </SideBtnWrap>
            </SidebarWrapper>
        </SidebarContainer>
    )
}

export default SideBar