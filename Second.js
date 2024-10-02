import { FlatList } from "react-native-gesture-handler";
import { styles } from "./Styles";
import { Text, TouchableOpacity, View, ScrollView, Dimensions } from 'react-native';
import { React, useState } from 'react';

const cards = [
    { name: "test", id: "1" },
    { name: "test2", id: "2" },
    { name: "test3", id: "3" },
    { name: "test4", id: "4" },
    { name: "test5", id: "5" },
    { name: "test6", id: "6" },
    { name: "test5", id: "7" },
    { name: "test6", id: "8" },
];




const Card = (card) => {
    console.log(`renderCard: ${card.item.name}`);
    if (card == null) {
        return (
            <View style={styles.squareShape}>
                <Text style={styles.text}>DEAD CARD</Text>
            </View>
        );
    } else {
        return (
            <View style={styles.squareShape}>
                <Text style={styles.text}>{card.item.name} -- {card.item.id}</Text>
            </View>
        );
    }
}



export const Second = (props) => {

    const renderItem = ({ item }) => {
        const backgroundColor = '#6e3b6e';
        return (
            <Card
                item={item}
                backgroundColor={backgroundColor}
                textColor={'#ffffff'}
            />
        );
    };



    const nextScreen = () => {
        props.navigation.push('Third');
    }


    return (
        <View style={styles.container}>
            <View style={styles.horizontalScrollContainer}>
                <Text style={styles.text}>Welcome to the Second Screen</Text>
                <TouchableOpacity style={styles.squareShape}>
                    <Text style={styles.buttonText}>Test</Text>
                </TouchableOpacity>
                <ScrollView style={{ width: Dimensions.width }} nestedScrollEnabled scrollEnabled={true} horizontal={true} >
                    {cards.map(item => {
                        return (Card({ item: item }));
                    })}

                </ScrollView>

                <TouchableOpacity style={styles.button} onPress={nextScreen}>
                    <Text style={styles.buttonText}>Home Screen</Text>
                </TouchableOpacity>

            </View >
        </View>);
}
