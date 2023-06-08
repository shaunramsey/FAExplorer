import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { FACircle } from "FACircle";

const Stack = createStackNavigator();

const AppStack = () => {
    return (
        <Stack.Navigator screenOptions={{ headerShown: false }}>
            <Stack.Screen name="FACircle" component={FACircle} />
        </Stack.Navigator>
    );
}


const App = () => {
    return (
        < NavigationContainer >
            <Stack />
        </NavigationContainer >
    );
}


