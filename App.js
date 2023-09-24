import { React } from "react";
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { FACircle } from "./FACircle";
import { Second } from "./Second";
import { Third } from "./Third";
import { Login } from "./Login";


const Stack = createStackNavigator();

export default function App() {
    return (
        < NavigationContainer >
            <Stack.Navigator initialRouteName="Second"
                screenOptions={{
                    headerMode: 'screen',
                    headerTintColor: 'white',
                    headerStyle: { backgroundColor: 'green' },
                    headerShown: true
                }}>
                <Stack.Screen name="Login" component={Login} />
                <Stack.Screen name="FACircle" component={FACircle} />
                <Stack.Screen name="Second" component={Second} />
                <Stack.Screen name="Third" component={Third} />
            </Stack.Navigator>1
        </NavigationContainer >
    );
}


