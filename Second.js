import { FlatList } from "react-native-gesture-handler";
import { styles } from "./Styles";
import { Text, TouchableOpacity, View, ScrollView } from 'react-native';
import { React, useState } from 'react';

const cards = [
    { name: "test", id: "1" },
    { name: "test2", id: "2" }
];


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


    const nextScreen = () => {
        props.navigation.push('Third');
    }


    return (
        <View style={styles.container}>
            <Text style={styles.text}>Welcome to the Second Screen</Text>
            <TouchableOpacity style={styles.squareShape}>
                <Text style={styles.buttonText}>Test</Text>
            </TouchableOpacity>
            <ScrollView horizontal="true">
                <View style={styles.container}>
                    <FlatList
                        horizontal
                        data={cards}
                        renderItem={renderItem}
                        keyExtractor={item => item.id}
                    />
                </View>
            </ScrollView>

            <TouchableOpacity style={styles.button} onPress={nextScreen}>
                <Text style={styles.buttonText}>Home Screen</Text>
            </TouchableOpacity>

        </View>);
}
