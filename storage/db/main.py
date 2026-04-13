import podcast


def main():
    guid = "d41c3b4f-f078-426e-812f-1684791caf19"
    try:
        pc = podcast.get(guid)
        print(pc)
    except Exception as e:
        print(f"Error occured: {e}")


if __name__ == "__main__":
    # main()
    connection_test()
