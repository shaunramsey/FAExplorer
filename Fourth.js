<FlatList
    horizontal

    data={cards}
    renderItem={renderItem}
    keyExtractor={item => item.id}
    style={{ width: Dimensions.width }}
/>