import { React } from "react";
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { FACircle } from "FACircle";


const Stack = createStackNavigator();

export default function App() {
    return (
        < NavigationContainer >
            <Stack.Navigator screenOptions={{ headerShown: false }}>
                <Stack.Screen name="FACircle" component={FACircle} />
            </Stack.Navigator>1
        </NavigationContainer >
    );
}


